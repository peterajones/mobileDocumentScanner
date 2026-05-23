# Mobile Document Scanner — Plan 2b: Per-page crop / rotate editor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user fix a single page after the fact — adjust the crop quadrilateral (with auto-detection as a starting point) and rotate in 90° increments. The corrected page replaces the original in the PDF and is re-OCR'd so search continues to work.

**Architecture:** A new full-screen `.sheet`-presented `PageEditorView` shows the page image with a draggable 4-corner quad overlay (initialized via `VNDetectDocumentSegmentationRequest`) and two rotation buttons. On Apply, the editor builds the new page image via `PerspectiveCorrector` (Core Image's `CIPerspectiveCorrection`) and any rotation, runs OCR on it, and uses a new `DocumentMutations.replacePage` to swap it into the PDF. Re-OCR runs on every apply — simpler than the spec's split between rotation-only and crop paths, with a negligible CPU cost.

**Tech Stack:** SwiftUI, PDFKit, Vision (`VNDetectDocumentSegmentationRequest`, `VNRecognizeTextRequest`), Core Image (`CIPerspectiveCorrection`), Core Graphics for image rotation.

**Spec:** [`docs/superpowers/specs/2026-05-21-mobile-document-scanner-design.md`](../specs/2026-05-21-mobile-document-scanner-design.md) — Edit-mode per-page editor.

**Prerequisite plan:** [Plan 2a](2026-05-22-mobile-document-scanner-plan-2a-viewer-and-page-ops.md) must be completed and verified on device.

---

## A note for the first-time iOS developer

Plan 2b is the most UI-heavy plan in the series — custom gesture handling and Core Image work. A few new iOS idioms used here:

- **Core Image (CI) filters.** Apple's image processing pipeline. `CIPerspectiveCorrection` takes a source image + 4 corner points (top-left, top-right, bottom-left, bottom-right) and outputs a rectified image. Chains naturally: `CIImage(image:)` → filter → `CIContext.createCGImage(_:from:)` → done.
- **`VNDetectDocumentSegmentationRequest`.** Vision's "find the document edges in this photo" request. Returns `VNRectangleObservation` with corner points in **normalized image coordinates** (0…1, origin at bottom-left, y-up). We'll convert to pixel coordinates with origin top-left, y-down.
- **`.gesture` + `DragGesture`.** SwiftUI's drag handling. We attach one to each corner handle and convert the drag translation to an image-space delta.
- **`GeometryReader`.** Lets a view know its rendered size — needed because the page image is displayed at some scaled size on screen, and we need to map screen-coordinate drags back to image coordinates.

## File structure (target end-state of Plan 2b)

```text
DocumentScanner/
  PageEditor/                               # NEW module
    Quad.swift                              # value type: 4 corners + clamp/normalize helpers
    PerspectiveCorrector.swift              # CIPerspectiveCorrection wrapper
    DocumentSegmenter.swift                 # async wrapper around VNDetectDocumentSegmentationRequest
    PageImageRenderer.swift                 # PDFPage → UIImage at native size
    QuadOverlay.swift                       # SwiftUI view: image + 4 draggable corner handles
    PageEditorView.swift                    # the full-screen sheet
  Pipeline/
    DocumentMutations.swift                 # ADD: replacePage(in:at:with:)
  Viewer/
    EditModeView.swift                      # MODIFY: tap thumbnail → present PageEditorView
DocumentScannerTests/
  QuadTests.swift                           # NEW
  PerspectiveCorrectorTests.swift           # NEW
  DocumentSegmenterTests.swift              # NEW
  DocumentMutationsTests.swift              # ADD: replacePage cases
  PageImageRendererTests.swift              # NEW
```

After Plan 2b: in edit mode, tapping a thumbnail opens the editor sheet over the viewer. The page is shown with an auto-detected quad. Drag corners to refine. Tap `↻`/`↺` to rotate. Tap **Apply** — the page is corrected, rotated if needed, re-OCR'd, and written back to the PDF at the same index. Cancel dismisses without changes.

---

## Task 1: Quad value type

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/Quad.swift`
- Create: `DocumentScanner/DocumentScannerTests/QuadTests.swift`

A small value type holding 4 corners. All coordinates are in image pixel space (origin top-left, y-down). Used by the editor to track quad state and by `PerspectiveCorrector` to apply the transform.

- [ ] **Step 1: Write the failing tests**

  `DocumentScannerTests/QuadTests.swift`:

  ```swift
  import XCTest
  import CoreGraphics
  @testable import DocumentScanner

  final class QuadTests: XCTestCase {

      func test_init_storesFourCorners() {
          let q = Quad(
              topLeft: CGPoint(x: 0, y: 0),
              topRight: CGPoint(x: 100, y: 0),
              bottomRight: CGPoint(x: 100, y: 200),
              bottomLeft: CGPoint(x: 0, y: 200)
          )
          XCTAssertEqual(q.topLeft, CGPoint(x: 0, y: 0))
          XCTAssertEqual(q.topRight, CGPoint(x: 100, y: 0))
          XCTAssertEqual(q.bottomRight, CGPoint(x: 100, y: 200))
          XCTAssertEqual(q.bottomLeft, CGPoint(x: 0, y: 200))
      }

      func test_fullRect_fillsBounds() {
          let bounds = CGSize(width: 800, height: 600)
          let q = Quad.fullRect(in: bounds)
          XCTAssertEqual(q.topLeft, CGPoint(x: 0, y: 0))
          XCTAssertEqual(q.topRight, CGPoint(x: 800, y: 0))
          XCTAssertEqual(q.bottomRight, CGPoint(x: 800, y: 600))
          XCTAssertEqual(q.bottomLeft, CGPoint(x: 0, y: 600))
      }

      func test_clamped_movesPointsInsideBounds() {
          let q = Quad(
              topLeft: CGPoint(x: -50, y: -50),
              topRight: CGPoint(x: 9999, y: 0),
              bottomRight: CGPoint(x: 9999, y: 9999),
              bottomLeft: CGPoint(x: 0, y: 9999)
          )
          let bounds = CGSize(width: 800, height: 600)
          let clamped = q.clamped(to: bounds)
          XCTAssertEqual(clamped.topLeft, CGPoint(x: 0, y: 0))
          XCTAssertEqual(clamped.topRight, CGPoint(x: 800, y: 0))
          XCTAssertEqual(clamped.bottomRight, CGPoint(x: 800, y: 600))
          XCTAssertEqual(clamped.bottomLeft, CGPoint(x: 0, y: 600))
      }

      func test_corners_returnsAllFourInTRBLOrder() {
          let q = Quad.fullRect(in: CGSize(width: 100, height: 100))
          XCTAssertEqual(q.corners, [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft])
      }
  }
  ```

- [ ] **Step 2: Run, see failure**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild test -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' -only-testing:DocumentScannerTests/QuadTests 2>&1 | tail -10
  ```

- [ ] **Step 3: Implement `Quad`**

  `DocumentScanner/DocumentScanner/PageEditor/Quad.swift`:

  ```swift
  import CoreGraphics

  /// Four-corner shape in image pixel coordinates (origin top-left, y-down).
  /// Corner naming uses the document's own orientation, not the screen's:
  /// `topLeft` is the upper-left when the document is shown right-side-up.
  struct Quad: Equatable {
      var topLeft: CGPoint
      var topRight: CGPoint
      var bottomRight: CGPoint
      var bottomLeft: CGPoint

      var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

      static func fullRect(in size: CGSize) -> Quad {
          Quad(
              topLeft: .zero,
              topRight: CGPoint(x: size.width, y: 0),
              bottomRight: CGPoint(x: size.width, y: size.height),
              bottomLeft: CGPoint(x: 0, y: size.height)
          )
      }

      /// Returns a copy with each corner clamped into the given bounds.
      func clamped(to size: CGSize) -> Quad {
          Quad(
              topLeft: Self.clamp(topLeft, to: size),
              topRight: Self.clamp(topRight, to: size),
              bottomRight: Self.clamp(bottomRight, to: size),
              bottomLeft: Self.clamp(bottomLeft, to: size)
          )
      }

      private static func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
          CGPoint(
              x: min(max(0, point.x), size.width),
              y: min(max(0, point.y), size.height)
          )
      }
  }
  ```

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/Quad.swift DocumentScanner/DocumentScannerTests/QuadTests.swift
  git commit -m "Add Quad value type for per-page crop overlay

  Task 1 of plan-2b: simple four-corner shape with image-space
  coordinates, a full-rect convenience, and clamping to image
  bounds for corner-drag handling.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 2: PerspectiveCorrector — apply the crop

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/PerspectiveCorrector.swift`
- Create: `DocumentScanner/DocumentScannerTests/PerspectiveCorrectorTests.swift`

A small struct that takes a UIImage + Quad and returns the perspective-corrected UIImage. Wraps Core Image's `CIPerspectiveCorrection`.

- [ ] **Step 1: Write the failing tests**

  ```swift
  import XCTest
  import UIKit
  @testable import DocumentScanner

  final class PerspectiveCorrectorTests: XCTestCase {

      func test_correct_returnsImageWithReasonableDimensions() throws {
          // 200×300 source, quad covering the top half → expected ~200×150 output.
          let source = whiteImage(size: CGSize(width: 200, height: 300))
          let quad = Quad(
              topLeft: CGPoint(x: 0, y: 0),
              topRight: CGPoint(x: 200, y: 0),
              bottomRight: CGPoint(x: 200, y: 150),
              bottomLeft: CGPoint(x: 0, y: 150)
          )
          let corrected = try XCTUnwrap(PerspectiveCorrector().correct(source, quad: quad))
          XCTAssertEqual(corrected.size.width, 200, accuracy: 2)
          XCTAssertEqual(corrected.size.height, 150, accuracy: 2)
      }

      func test_correct_fullRectQuadReturnsImageOfOriginalSize() throws {
          let source = whiteImage(size: CGSize(width: 400, height: 600))
          let quad = Quad.fullRect(in: source.size)
          let corrected = try XCTUnwrap(PerspectiveCorrector().correct(source, quad: quad))
          XCTAssertEqual(corrected.size.width, 400, accuracy: 2)
          XCTAssertEqual(corrected.size.height, 600, accuracy: 2)
      }

      // MARK: - Helpers

      private func whiteImage(size: CGSize) -> UIImage {
          UIGraphicsImageRenderer(size: size).image { _ in
              UIColor.white.setFill()
              UIRectFill(CGRect(origin: .zero, size: size))
          }
      }
  }
  ```

- [ ] **Step 2: Run, see failure**

- [ ] **Step 3: Implement `PerspectiveCorrector`**

  ```swift
  import UIKit
  import CoreImage

  struct PerspectiveCorrector {

      /// Apply a perspective-correction transform to `source` using `quad`'s
      /// 4 corners as the new image rectangle. Returns nil if the transform
      /// cannot be applied (e.g., source has no cgImage).
      ///
      /// `quad` is in image pixel coordinates with origin top-left (y-down).
      /// Core Image uses origin bottom-left (y-up), so y values are flipped.
      func correct(_ source: UIImage, quad: Quad) -> UIImage? {
          guard let cgImage = source.cgImage else { return nil }
          let ciImage = CIImage(cgImage: cgImage)
          let h = ciImage.extent.height

          func flipped(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: h - p.y) }

          let filter = CIFilter(name: "CIPerspectiveCorrection")!
          filter.setValue(ciImage, forKey: kCIInputImageKey)
          filter.setValue(CIVector(cgPoint: flipped(quad.topLeft)), forKey: "inputTopLeft")
          filter.setValue(CIVector(cgPoint: flipped(quad.topRight)), forKey: "inputTopRight")
          filter.setValue(CIVector(cgPoint: flipped(quad.bottomRight)), forKey: "inputBottomRight")
          filter.setValue(CIVector(cgPoint: flipped(quad.bottomLeft)), forKey: "inputBottomLeft")

          guard let output = filter.outputImage else { return nil }
          let context = CIContext()
          guard let outCG = context.createCGImage(output, from: output.extent) else { return nil }
          return UIImage(cgImage: outCG, scale: 1, orientation: .up)
      }
  }
  ```

  > Web-dev framing: Core Image filters are basically `transform(input) → output` shaders. `CIPerspectiveCorrection` is the four-point unwarp transform — give it where the document's four corners are in the source image and it gives you back a rectified rectangular image.

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/PerspectiveCorrector.swift DocumentScanner/DocumentScannerTests/PerspectiveCorrectorTests.swift
  git commit -m "Add PerspectiveCorrector wrapping CIPerspectiveCorrection

  Task 2 of plan-2b: applies a four-point unwarp to a source UIImage
  using the user's adjusted Quad. Output is the rectified rectangular
  image. Flips y-axis between our top-left coordinate space and
  Core Image's bottom-left convention.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 3: DocumentSegmenter — auto-detect the initial quad

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/DocumentSegmenter.swift`
- Create: `DocumentScanner/DocumentScannerTests/DocumentSegmenterTests.swift`

Async wrapper around `VNDetectDocumentSegmentationRequest`. Returns a `Quad?` in image pixel coordinates (top-left origin). Returns `nil` if no document edges are detected (e.g., a blank image).

- [ ] **Step 1: Write the failing test**

  Vision's segmentation request needs a real image to detect against. Easiest in tests: feed it a constructed image with a dark rectangle on a light background — Vision picks up the rectangle as a "document".

  ```swift
  import XCTest
  import UIKit
  @testable import DocumentScanner

  final class DocumentSegmenterTests: XCTestCase {

      func test_segment_returnsQuadForDocumentLikeImage() async throws {
          // Page with a black rectangle on white — Vision should find its edges.
          let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).image { _ in
              UIColor.white.setFill()
              UIRectFill(CGRect(x: 0, y: 0, width: 800, height: 1000))
              UIColor.black.setFill()
              UIRectFill(CGRect(x: 100, y: 150, width: 600, height: 700))
          }
          let segmenter = DocumentSegmenter()
          let quad = try await segmenter.detect(in: image)
          let quadUnwrapped = try XCTUnwrap(quad)
          // Should find something near our 600×700 inset; corners between (50, 100) and (750, 900).
          XCTAssertGreaterThan(quadUnwrapped.topRight.x, 400)
          XCTAssertGreaterThan(quadUnwrapped.bottomLeft.y, 500)
      }

      func test_segment_returnsNilForBlankImage() async throws {
          let blank = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { _ in
              UIColor.white.setFill()
              UIRectFill(CGRect(x: 0, y: 0, width: 400, height: 400))
          }
          let quad = try await DocumentSegmenter().detect(in: blank)
          XCTAssertNil(quad)
      }
  }
  ```

- [ ] **Step 2: Run, see failure**

- [ ] **Step 3: Implement `DocumentSegmenter`**

  ```swift
  @preconcurrency import Vision
  import UIKit
  import CoreGraphics

  enum DocumentSegmenterError: Error {
      case invalidImage
  }

  struct DocumentSegmenter {

      /// Detect document edges in `image`. Returns the corner quad in image-pixel
      /// coordinates (top-left origin), or `nil` if no document is found.
      ///
      /// Uses VNDetectDocumentSegmentationRequest which is the same underlying
      /// detection VisionKit's scanner uses, but exposed so we can re-run it on
      /// an already-captured image.
      func detect(in image: UIImage) async throws -> Quad? {
          guard let cgImage = image.cgImage else { throw DocumentSegmenterError.invalidImage }
          let size = CGSize(width: cgImage.width, height: cgImage.height)

          return try await withCheckedThrowingContinuation { continuation in
              let lock = NSLock()
              var hasResumed = false
              func tryResume(_ result: Result<Quad?, Error>) {
                  lock.lock(); defer { lock.unlock() }
                  guard !hasResumed else { return }
                  hasResumed = true
                  continuation.resume(with: result)
              }

              let request = VNDetectDocumentSegmentationRequest { request, error in
                  if let error = error { tryResume(.failure(error)); return }
                  guard let observations = request.results as? [VNRectangleObservation],
                        let observation = observations.first else {
                      tryResume(.success(nil))
                      return
                  }
                  tryResume(.success(Self.quad(from: observation, in: size)))
              }

              let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
              DispatchQueue.global(qos: .userInitiated).async {
                  do { try handler.perform([request]) }
                  catch { tryResume(.failure(error)) }
              }
          }
      }

      /// Convert a VNRectangleObservation (normalized 0–1 with origin bottom-left)
      /// into our image-pixel Quad (origin top-left).
      private static func quad(from observation: VNRectangleObservation, in size: CGSize) -> Quad {
          func denormalize(_ p: CGPoint) -> CGPoint {
              CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
          }
          return Quad(
              topLeft: denormalize(observation.topLeft),
              topRight: denormalize(observation.topRight),
              bottomRight: denormalize(observation.bottomRight),
              bottomLeft: denormalize(observation.bottomLeft)
          )
      }
  }
  ```

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/DocumentSegmenter.swift DocumentScanner/DocumentScannerTests/DocumentSegmenterTests.swift
  git commit -m "Add DocumentSegmenter wrapping VNDetectDocumentSegmentationRequest

  Task 3 of plan-2b: async wrapper that returns a Quad in image-pixel
  coordinates (top-left origin) or nil when no document is detected.
  Used to initialize the editor's crop overlay so the user starts
  with a reasonable suggestion rather than the full image.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 4: PageImageRenderer — extract a UIImage from a PDFPage

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/PageImageRenderer.swift`
- Create: `DocumentScanner/DocumentScannerTests/PageImageRendererTests.swift`

The editor needs the page's pixel content as a `UIImage` to feed into segmentation and perspective correction. `PDFPage` doesn't expose its embedded image directly; we rasterize at the page's native size.

- [ ] **Step 1: Write the failing test**

  ```swift
  import XCTest
  import PDFKit
  @testable import DocumentScanner

  final class PageImageRendererTests: XCTestCase {

      func test_render_producesImageAtPageSize() throws {
          // 100×100 source image → assembled into a one-page PDF.
          let source = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { _ in
              UIColor.white.setFill()
              UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
          }
          let pdf = try PDFAssembler().assemble(
              pages: [ScannedPage(image: source, recognizedStrings: [])],
              createdAt: Date()
          )
          let page = try XCTUnwrap(pdf.page(at: 0))
          let rendered = try XCTUnwrap(PageImageRenderer().image(from: page))
          XCTAssertEqual(rendered.size.width, 100, accuracy: 1)
          XCTAssertEqual(rendered.size.height, 100, accuracy: 1)
      }
  }
  ```

- [ ] **Step 2: Run, see failure**

- [ ] **Step 3: Implement `PageImageRenderer`**

  ```swift
  import UIKit
  import PDFKit

  /// Rasterizes a PDFPage to a UIImage at the page's native point dimensions
  /// (1pt = 1px, scale 1) — same convention PDFAssembler used to construct
  /// the page. Used by PageEditorView to feed the page into segmentation and
  /// perspective correction.
  struct PageImageRenderer {

      func image(from page: PDFPage) -> UIImage? {
          let bounds = page.bounds(for: .mediaBox)
          let format = UIGraphicsImageRendererFormat()
          format.scale = 1
          format.opaque = true
          let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
          return renderer.image { ctx in
              UIColor.white.setFill()
              ctx.fill(CGRect(origin: .zero, size: bounds.size))
              // PDFKit draws using its own coordinate system; we just hand it our context.
              ctx.cgContext.saveGState()
              page.draw(with: .mediaBox, to: ctx.cgContext)
              ctx.cgContext.restoreGState()
          }
      }
  }
  ```

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/PageImageRenderer.swift DocumentScanner/DocumentScannerTests/PageImageRendererTests.swift
  git commit -m "Add PageImageRenderer to rasterize a PDFPage into a UIImage

  Task 4 of plan-2b: produces a 1-pt-per-pixel UIImage of a page's
  mediaBox content. Used by PageEditorView to feed pages into
  segmentation, perspective correction, and re-OCR.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 5: DocumentMutations.replacePage

**Files:**
- Modify: `DocumentScanner/DocumentScanner/Pipeline/DocumentMutations.swift`
- Modify: `DocumentScanner/DocumentScannerTests/DocumentMutationsTests.swift`

Add a `replacePage` operation: swap the page at index N for a page from a one-page PDF.

- [ ] **Step 1: Add the failing test**

  Append to `DocumentMutationsTests.swift`:

  ```swift
  func test_replacePage_swapsThePageAtIndex() throws {
      let pdf = try threePagePDF()       // [A, B, C]
      let replacement = try singlePagePDF(marker: "X")
      DocumentMutations.replacePage(in: pdf, at: 1, with: replacement)
      XCTAssertEqual(pageMarkers(pdf), ["A", "X", "C"])
  }
  ```

- [ ] **Step 2: Run, see failure**

- [ ] **Step 3: Implement**

  Add to `DocumentMutations.swift`:

  ```swift
  /// Replace the page at `index` in `pdf` with the first page of `replacement`.
  /// No-op if either bound is invalid.
  static func replacePage(in pdf: PDFDocument, at index: Int, with replacement: PDFDocument) {
      guard index >= 0, index < pdf.pageCount,
            let newPage = replacement.page(at: 0) else { return }
      pdf.removePage(at: index)
      pdf.insert(newPage, at: index)
  }
  ```

- [ ] **Step 4: Test passes**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Pipeline/DocumentMutations.swift DocumentScanner/DocumentScannerTests/DocumentMutationsTests.swift
  git commit -m "DocumentMutations: replacePage(in:at:with:)

  Task 5 of plan-2b: swap one page out for another, preserving the
  ordering of the rest. PageEditorView uses this on Apply.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 6: QuadOverlay SwiftUI view

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/QuadOverlay.swift`

A SwiftUI view that shows the page image with 4 draggable corner handles + lines connecting them. Pure presentation — owns no business logic; receives a `Binding<Quad>` and the underlying image.

No unit tests for this view (gesture-driven UI). Verification: build + visual inspection in the device smoke test.

- [ ] **Step 1: Implement the view**

  ```swift
  import SwiftUI

  struct QuadOverlay: View {
      let image: UIImage
      @Binding var quad: Quad

      var body: some View {
          GeometryReader { geo in
              let imageSize = image.size
              let viewSize = geo.size
              let scale = min(viewSize.width / imageSize.width,
                              viewSize.height / imageSize.height)
              let displayedSize = CGSize(width: imageSize.width * scale,
                                         height: imageSize.height * scale)
              let offsetX = (viewSize.width - displayedSize.width) / 2
              let offsetY = (viewSize.height - displayedSize.height) / 2

              ZStack(alignment: .topLeading) {
                  Image(uiImage: image)
                      .resizable()
                      .scaledToFit()

                  // Quad outline.
                  Path { path in
                      let pts = quad.corners.map { p in
                          CGPoint(x: offsetX + p.x * scale,
                                  y: offsetY + p.y * scale)
                      }
                      path.move(to: pts[0])
                      path.addLine(to: pts[1])
                      path.addLine(to: pts[2])
                      path.addLine(to: pts[3])
                      path.closeSubpath()
                  }
                  .stroke(Color.accentColor, lineWidth: 2)

                  // 4 corner handles.
                  handle(at: \.topLeft, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
                  handle(at: \.topRight, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
                  handle(at: \.bottomRight, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
                  handle(at: \.bottomLeft, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
              }
          }
          .aspectRatio(image.size, contentMode: .fit)
      }

      @ViewBuilder
      private func handle(at corner: WritableKeyPath<Quad, CGPoint>,
                          scale: CGFloat,
                          offset: CGPoint,
                          imageSize: CGSize) -> some View {
          let point = quad[keyPath: corner]
          let screenPoint = CGPoint(x: offset.x + point.x * scale,
                                    y: offset.y + point.y * scale)

          Circle()
              .fill(Color.white)
              .frame(width: 24, height: 24)
              .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
              .shadow(radius: 2)
              .position(screenPoint)
              .gesture(
                  DragGesture()
                      .onChanged { value in
                          let newScreenX = value.location.x
                          let newScreenY = value.location.y
                          let newImagePoint = CGPoint(
                              x: (newScreenX - offset.x) / scale,
                              y: (newScreenY - offset.y) / scale
                          )
                          var next = quad
                          next[keyPath: corner] = newImagePoint
                          quad = next.clamped(to: imageSize)
                      }
              )
      }
  }
  ```

- [ ] **Step 2: Build**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild build -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' 2>&1 | grep -E "warning:|error:|BUILD (SUCC|FAIL)" | grep -v "^ld:\|appintentsmetadataprocessor" | head -10
  ```

  Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/QuadOverlay.swift
  git commit -m "Add QuadOverlay SwiftUI view: image + 4 draggable corners

  Task 6 of plan-2b: presentation-only view. Shows an image with
  a four-sided polygon outline and 24pt circular handles at each
  corner. Drag a handle to move that corner in image-space
  coordinates; the new position is clamped to image bounds.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 7: PageEditorView — the full editor sheet

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/PageEditorView.swift`

The full-screen sheet. On appear, renders the page, runs auto-detect, sets the initial quad. UI: image with QuadOverlay, rotation buttons, Cancel/Apply nav-bar buttons. On Apply: perspective-correct → rotate → re-OCR → build a one-page PDF via PDFAssembler → call `DocumentMutations.replacePage` → save via `DocumentSession`.

No unit tests for this view (orchestration + UI). Verified in device smoke test.

- [ ] **Step 1: Implement `PageEditorView`**

  ```swift
  import SwiftUI
  import PDFKit
  import UIKit

  /// Full-screen sheet for editing a single page's crop and rotation.
  /// Mutates the passed-in DocumentSession on Apply and saves.
  struct PageEditorView: View {
      @Bindable var session: DocumentSession
      let pageIndex: Int
      let onDismiss: () -> Void

      private let renderer = PageImageRenderer()
      private let segmenter = DocumentSegmenter()
      private let corrector = PerspectiveCorrector()
      private let ocr = OCREngine()

      @State private var pageImage: UIImage?
      @State private var quad: Quad?
      @State private var rotationQuarterTurns = 0  // 0/1/2/3 → 0°/90°/180°/270° CW
      @State private var isWorking = false
      @State private var errorMessage: String?

      var body: some View {
          NavigationStack {
              Group {
                  if let pageImage, let quadBinding {
                      VStack(spacing: 8) {
                          QuadOverlay(image: rotatedImage(pageImage), quad: quadBinding)
                              .padding()
                          rotationControls
                          if let errorMessage {
                              Text(errorMessage).foregroundStyle(.red).font(.footnote)
                          }
                      }
                  } else {
                      ProgressView("Preparing page…")
                  }
              }
              .navigationTitle("Edit Page \(pageIndex + 1)")
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                  ToolbarItem(placement: .cancellationAction) {
                      Button("Cancel") { onDismiss() }.disabled(isWorking)
                  }
                  ToolbarItem(placement: .confirmationAction) {
                      if isWorking {
                          ProgressView()
                      } else {
                          Button("Apply") { Task { await applyEdit() } }
                              .disabled(quad == nil)
                      }
                  }
              }
              .task { await prepare() }
              .interactiveDismissDisabled(isWorking)
          }
      }

      private var quadBinding: Binding<Quad>? {
          guard quad != nil else { return nil }
          return Binding(
              get: { quad ?? Quad.fullRect(in: pageImage?.size ?? .zero) },
              set: { quad = $0 }
          )
      }

      private var rotationControls: some View {
          HStack(spacing: 24) {
              Button {
                  rotationQuarterTurns = (rotationQuarterTurns + 3) % 4   // counter-clockwise
              } label: {
                  Image(systemName: "rotate.left").font(.title2)
              }
              Text("Rotation: \(rotationQuarterTurns * 90)°").font(.footnote).monospaced()
              Button {
                  rotationQuarterTurns = (rotationQuarterTurns + 1) % 4   // clockwise
              } label: {
                  Image(systemName: "rotate.right").font(.title2)
              }
          }
          .padding(.bottom, 16)
      }

      private func prepare() async {
          guard let page = session.pdf.page(at: pageIndex),
                let rendered = renderer.image(from: page) else {
              errorMessage = "Couldn't render page \(pageIndex + 1)."
              return
          }
          pageImage = rendered
          quad = (try? await segmenter.detect(in: rendered)) ?? Quad.fullRect(in: rendered.size)
      }

      private func rotatedImage(_ image: UIImage) -> UIImage {
          guard rotationQuarterTurns != 0 else { return image }
          // Apply rotation to the displayed image only. The actual quad still
          // operates in the underlying image's coordinate space; the apply
          // step rotates the corrected output, not the source.
          let angle = CGFloat(rotationQuarterTurns) * .pi / 2
          let size: CGSize = (rotationQuarterTurns % 2 == 0)
              ? image.size
              : CGSize(width: image.size.height, height: image.size.width)
          let renderer = UIGraphicsImageRenderer(size: size)
          return renderer.image { ctx in
              ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
              ctx.cgContext.rotate(by: angle)
              image.draw(in: CGRect(x: -image.size.width / 2,
                                    y: -image.size.height / 2,
                                    width: image.size.width,
                                    height: image.size.height))
          }
      }

      private func applyEdit() async {
          guard let pageImage, let quad else { return }
          isWorking = true
          defer { isWorking = false }
          do {
              guard let corrected = corrector.correct(pageImage, quad: quad) else {
                  errorMessage = "Couldn't apply crop."
                  return
              }
              let finalImage = rotatedImage(corrected)
              let strings = (try? await ocr.recognizeText(in: finalImage)) ?? []
              let newDoc = try PDFAssembler().assemble(
                  pages: [ScannedPage(image: finalImage, recognizedStrings: strings)],
                  createdAt: Date()
              )
              DocumentMutations.replacePage(in: session.pdf, at: pageIndex, with: newDoc)
              _ = try session.save()
              onDismiss()
          } catch {
              errorMessage = error.localizedDescription
          }
      }
  }
  ```

  > Web-dev framing: the editor is a self-contained sheet that pulls the page bytes, asks Vision for a quad, renders an overlay, and on Apply runs the whole edit pipeline (crop → rotate → OCR → assemble → swap) before dismissing. The DocumentSession is the source of truth for the document being edited.

- [ ] **Step 2: Build**

  Expected `** BUILD SUCCEEDED **`. Strict-concurrency warnings here are plausible (the `@Bindable` of a `@MainActor` session, async OCR, etc.). Report exactly what they say if any appear.

- [ ] **Step 3: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/PageEditorView.swift
  git commit -m "Add PageEditorView: full-screen per-page crop/rotate editor

  Task 7 of plan-2b: orchestrates the whole edit flow inside a
  modal sheet. On appear: render the page, auto-detect a quad. UI:
  QuadOverlay + 90°-rotation controls. On Apply: perspective-correct
  via the user's quad, rotate, re-OCR, build a one-page PDF, and
  swap it into the document via DocumentMutations.replacePage.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 8: Wire entry — tap a thumbnail to edit

**Files:**
- Modify: `DocumentScanner/DocumentScanner/Viewer/EditModeView.swift`

Add a tap gesture on each thumbnail that surfaces a request to present the editor at that index. EditModeView publishes via a callback so DocumentViewerView can host the actual sheet.

- [ ] **Step 1: Add `onEditPage` callback property**

  In `EditModeView`, add:

  ```swift
  let onEditPage: (Int) -> Void
  ```

  next to `let onAddPages: () -> Void`.

- [ ] **Step 2: Add `.onTapGesture` to each thumbnail**

  In `EditModeView.thumbnail(at:)`, add after `.contextMenu { ... }`:

  ```swift
  .onTapGesture {
      onEditPage(index)
  }
  ```

- [ ] **Step 3: Host the editor sheet in `DocumentViewerView`**

  In `DocumentScanner/DocumentScanner/Viewer/DocumentViewerView.swift`, add:

  ```swift
  @State private var editingPageIndex: Int?
  ```

  near the other state. In `loadedBody`, pass to `EditModeView`:

  ```swift
  EditModeView(
      session: session,
      onEditPage: { editingPageIndex = $0 },
      onAddPages: { showAddPages = true }
  )
  ```

  And add a `.sheet(item:)` for the editor, near the other modifiers:

  ```swift
  .sheet(item: Binding(
      get: { editingPageIndex.map { PageEditorContext(index: $0) } },
      set: { editingPageIndex = $0?.index }
  )) { ctx in
      PageEditorView(
          session: session,
          pageIndex: ctx.index,
          onDismiss: { editingPageIndex = nil }
      )
  }
  ```

  Add the `PageEditorContext` helper struct at the top of `DocumentViewerView` (inside the struct):

  ```swift
  private struct PageEditorContext: Identifiable {
      let index: Int
      var id: Int { index }
  }
  ```

- [ ] **Step 4: Build**

  Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/Viewer/EditModeView.swift DocumentScanner/DocumentScanner/Viewer/DocumentViewerView.swift
  git commit -m "Edit mode: tap a thumbnail to open the per-page editor

  Task 8 of plan-2b: wires EditModeView's onEditPage callback to
  DocumentViewerView, which presents PageEditorView as a sheet at
  the tapped index. The sheet's PageEditorContext wrapper makes the
  index Identifiable for SwiftUI's item-based sheet presentation.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 9: Device smoke test

- [ ] **Step 1: Cmd+R to a real iPhone**

- [ ] **Step 2: Open a document with at least 2 pages** (scan another if needed).

- [ ] **Step 3: Tap Edit** → strip appears at the bottom.

- [ ] **Step 4: Tap a thumbnail** → the per-page editor sheet slides up:
  - Page image fills most of the screen
  - 4 corner handles + outlining quad overlay are visible
  - Auto-detected quad should roughly match the document edges (or fall back to full-image rect if detection fails)
  - Rotation buttons + rotation degree visible below the image
  - Apply/Cancel in the nav bar

- [ ] **Step 5: Test corner drag**
  - Drag one corner inward by ~50pt. The quad outline updates live.
  - Drag past the image bounds — corner clamps at the edge.

- [ ] **Step 6: Test rotation**
  - Tap rotate-right (↻). Image rotates 90° CW; quad stays attached to the underlying image (you may see corner positions look different — that's expected, the quad is in the underlying-image coordinate space).
  - Tap again — 180°. And again — 270°. And again — back to 0°.

- [ ] **Step 7: Test Apply**
  - Adjust the quad to crop into the document.
  - Set rotation if desired.
  - Tap Apply → spinner appears in the nav bar. After 1-3 seconds the sheet dismisses.
  - The thumbnail strip in EditMode should update to show the new (cropped + rotated) page.
  - Tap the new thumbnail to verify it's the corrected page.

- [ ] **Step 8: Test Cancel**
  - Tap another thumbnail. Dismiss with Cancel. No changes to the document.

- [ ] **Step 9: Sanity in Files.app**
  - Open Files.app → iCloud Drive → Document Scanner → your file. The corrected page should be reflected.
  - Long-press a word in the cropped page — selection menu appears if OCR ran successfully.

- [ ] **Step 10: Commit milestone**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git commit --allow-empty -m "Milestone: Plan 2b verified end-to-end on device"
  ```

---

## After Plan 2b

What lands:

- Per-page editor with auto-detected initial crop, draggable 4-corner overlay, 90° rotation, and full re-OCR after apply
- `DocumentMutations.replacePage` for swapping a page in place

What remains in the original spec:

- **Plan 3** — Settings + optional Face ID app lock + backgrounding blur
- **Plan 4** — Error edge cases (iCloud unavailable, conflicts, corrupt PDFs, storage full)
- **Plan 5** — XCUITest golden-path tests with mocked scanner

## Self-review notes

- Spec coverage: tap-thumbnail-to-edit ✓, auto-detected quad ✓, draggable corners ✓, rotation ✓, apply with re-OCR ✓, replace page ✓. Spec's split between "rotation-only no re-OCR" and "crop triggers re-OCR" simplified to always-re-OCR per the brainstorm.
- Placeholder scan: none.
- Type consistency: `Quad`, `PerspectiveCorrector`, `DocumentSegmenter`, `PageImageRenderer`, `DocumentMutations.replacePage`, `PageEditorView` — signatures match across all consumers.
- Test coverage: unit tests for Quad (4 cases), PerspectiveCorrector (2), DocumentSegmenter (2), PageImageRenderer (1), DocumentMutations.replacePage (1). UI tasks (QuadOverlay, PageEditorView, EditModeView wiring) verified via device smoke test.
- Risk: rotation interacts with quad coordinate space. The implementation applies rotation only to the displayed image; the quad still operates in the underlying image's coordinate frame. Apply then crops first, rotates the *output*. Visual fidelity to be confirmed in smoke test step 6.

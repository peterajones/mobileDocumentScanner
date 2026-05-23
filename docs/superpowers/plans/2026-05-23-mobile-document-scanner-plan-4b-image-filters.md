# Mobile Document Scanner — Plan 4b: Image filter presets

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a visual filter for any page in the per-page editor. Presets: Color (default), Greyscale, Black & White, Photo. The filtered image is what gets re-OCR'd and written back to the PDF on Apply.

**Architecture:** A small `ImageFilter` enum + `ImageFilterEngine` Core Image wrapper. `PageEditorView` gains a horizontal filter picker below the rotation controls; the selected filter is applied between rotation and OCR in `applyEdit`. Re-OCR runs on the filtered image because high-contrast B&W often improves recognition.

**Tech Stack:** Core Image (`CIColorMonochrome`, `CIColorControls`, `CIPhotoEffectNoir`), SwiftUI Picker.

**Spec:** Not in the original design doc — user feature request after Plan 4. The original scans look subdued; preset filters are the iOS-conventional way to give users punchier results without continuous-slider complexity.

**Prerequisite plans:** Plans 1, 2a, 2b, 3, 2c, 4 all completed and verified on device.

---

## A note for the first-time iOS developer

Core Image (CI) filters are simple pipelines: `CIImage(input)` → filter → `CIContext.createCGImage(output)` → done. Each filter is a named string ("CIColorMonochrome") with input keys you set via `setValue(_:forKey:)`. The output is another `CIImage`; the `CIContext` rasterizes it back to a `CGImage`.

For document filters, three CI filters cover almost everything:

- **`CIColorControls`** — knobs for `inputSaturation`, `inputBrightness`, `inputContrast`. Setting saturation to 0 gives greyscale; bumping contrast gives the "Photo" punch.
- **`CIColorMonochrome`** — converts to a single hue (we use white→black for B&W).
- **`CIPhotoEffectNoir`** — Apple's preset B&W, high contrast. Cleaner than a hand-tuned monochrome.

## File structure (target end-state of Plan 4b)

```text
DocumentScanner/
  PageEditor/
    ImageFilter.swift                       # NEW: enum + Core Image apply()
    PageEditorView.swift                    # MODIFY: filter picker + threading through applyEdit
DocumentScannerTests/
  ImageFilterTests.swift                    # NEW: filter applies and produces image of correct dims
```

After Plan 4b: open per-page editor → segment of buttons below rotation controls shows Color / Greyscale / B&W / Photo → tap one → live preview updates → Apply writes the filtered + re-OCR'd page back.

---

## Task 1: ImageFilter helper

**Files:**
- Create: `DocumentScanner/DocumentScanner/PageEditor/ImageFilter.swift`
- Create: `DocumentScanner/DocumentScannerTests/ImageFilterTests.swift`

Follow TDD.

- [ ] **Step 1: Write the failing tests**

  ```swift
  import XCTest
  import UIKit
  @testable import DocumentScanner

  final class ImageFilterTests: XCTestCase {

      func test_none_returnsSameDimensions() throws {
          let source = colorImage(width: 100, height: 200)
          let result = try XCTUnwrap(ImageFilterEngine().apply(.none, to: source))
          XCTAssertEqual(result.size.width, 100, accuracy: 1)
          XCTAssertEqual(result.size.height, 200, accuracy: 1)
      }

      func test_greyscale_returnsSameDimensions() throws {
          let source = colorImage(width: 100, height: 100)
          let result = try XCTUnwrap(ImageFilterEngine().apply(.greyscale, to: source))
          XCTAssertEqual(result.size.width, 100, accuracy: 1)
          XCTAssertEqual(result.size.height, 100, accuracy: 1)
      }

      func test_blackAndWhite_returnsSameDimensions() throws {
          let source = colorImage(width: 100, height: 100)
          let result = try XCTUnwrap(ImageFilterEngine().apply(.blackAndWhite, to: source))
          XCTAssertEqual(result.size.width, 100, accuracy: 1)
          XCTAssertEqual(result.size.height, 100, accuracy: 1)
      }

      func test_photo_returnsSameDimensions() throws {
          let source = colorImage(width: 100, height: 100)
          let result = try XCTUnwrap(ImageFilterEngine().apply(.photo, to: source))
          XCTAssertEqual(result.size.width, 100, accuracy: 1)
          XCTAssertEqual(result.size.height, 100, accuracy: 1)
      }

      // MARK: - Helpers

      private func colorImage(width: CGFloat, height: CGFloat) -> UIImage {
          UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
              UIColor.red.setFill()
              UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
              UIColor.blue.setFill()
              UIRectFill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
          }
      }
  }
  ```

- [ ] **Step 2: Run, see failure**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild test -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' -only-testing:DocumentScannerTests/ImageFilterTests 2>&1 | tail -10
  ```

- [ ] **Step 3: Implement `ImageFilter` + `ImageFilterEngine`**

  ```swift
  import UIKit
  import CoreImage
  import CoreImage.CIFilterBuiltins

  /// Visual filter applied to a page image in the editor. Preset-style;
  /// no continuous sliders.
  enum ImageFilter: String, CaseIterable, Identifiable {
      case none, greyscale, blackAndWhite, photo

      var id: String { rawValue }

      var displayName: String {
          switch self {
          case .none: return "Color"
          case .greyscale: return "Greyscale"
          case .blackAndWhite: return "B&W"
          case .photo: return "Photo"
          }
      }
  }

  struct ImageFilterEngine {

      private let context = CIContext()

      /// Apply `filter` to `source`. Returns the filtered UIImage or nil if
      /// the source has no cgImage.
      func apply(_ filter: ImageFilter, to source: UIImage) -> UIImage? {
          guard filter != .none else { return source }
          guard let cgImage = source.cgImage else { return nil }
          let ciImage = CIImage(cgImage: cgImage)
          guard let output = filteredImage(filter, input: ciImage),
                let outCG = context.createCGImage(output, from: ciImage.extent) else {
              return nil
          }
          return UIImage(cgImage: outCG, scale: 1, orientation: .up)
      }

      private func filteredImage(_ filter: ImageFilter, input: CIImage) -> CIImage? {
          switch filter {
          case .none:
              return input
          case .greyscale:
              let f = CIFilter.colorControls()
              f.inputImage = input
              f.saturation = 0
              return f.outputImage
          case .blackAndWhite:
              // CIPhotoEffectNoir is Apple's high-contrast B&W preset —
              // cleaner than rolling our own monochrome + contrast bump.
              let f = CIFilter.photoEffectNoir()
              f.inputImage = input
              return f.outputImage
          case .photo:
              // Punch up contrast + saturation for photos / glossy pages.
              let f = CIFilter.colorControls()
              f.inputImage = input
              f.saturation = 1.2
              f.contrast = 1.15
              return f.outputImage
          }
      }
  }
  ```

- [ ] **Step 4: Tests pass**

- [ ] **Step 5: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/ImageFilter.swift DocumentScanner/DocumentScannerTests/ImageFilterTests.swift
  git commit -m "Add ImageFilter enum + Core Image wrapper

  Task 1 of plan-4b: 4 preset filters (Color, Greyscale, B&W,
  Photo) backed by CIColorControls and CIPhotoEffectNoir. Pure
  helper — no UI yet.

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 2: Filter picker in PageEditorView

**Files:**
- Modify: `DocumentScanner/DocumentScanner/PageEditor/PageEditorView.swift`

Adds a horizontal segmented filter picker below the rotation controls, with a live preview applied to the displayed image. On Apply, the chosen filter is applied to the corrected+rotated image before OCR.

- [ ] **Step 1: Add state + threading**

  In `PageEditorView`, add an `@State` near the others:

  ```swift
  @State private var filter: ImageFilter = .none
  ```

  And add an `ImageFilterEngine` alongside the other helpers:

  ```swift
  private let filterEngine = ImageFilterEngine()
  ```

- [ ] **Step 2: Apply filter to the displayed image**

  The current preview-rendering helper is `rotatedImage(_:)`. Wrap its output through the filter for display so the user sees a live preview:

  Add a new helper:

  ```swift
  private func displayedImage(_ image: UIImage) -> UIImage {
      let rotated = rotatedImage(image)
      return filterEngine.apply(filter, to: rotated) ?? rotated
  }
  ```

  Replace the body's `QuadOverlay(image: rotatedImage(pageImage), quad: quadBinding)` call with:

  ```swift
  QuadOverlay(image: displayedImage(pageImage), quad: quadBinding)
  ```

- [ ] **Step 3: Add the filter picker UI**

  In the `body`, add a horizontal picker below `rotationControls`. The whole `VStack(spacing: 8)` body currently has:

  ```swift
  VStack(spacing: 8) {
      QuadOverlay(...)
          .padding()
      rotationControls
      if let errorMessage {
          Text(errorMessage)...
      }
  }
  ```

  Insert `filterControls` between `rotationControls` and the error text:

  ```swift
  VStack(spacing: 8) {
      QuadOverlay(...)
          .padding()
      rotationControls
      filterControls
      if let errorMessage {
          Text(errorMessage)...
      }
  }
  ```

  Add a computed view at the same level as `rotationControls`:

  ```swift
  private var filterControls: some View {
      Picker("Filter", selection: $filter) {
          ForEach(ImageFilter.allCases) { f in
              Text(f.displayName).tag(f)
          }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal)
  }
  ```

- [ ] **Step 4: Thread filter through `applyEdit`**

  In `applyEdit`, after `rotatedImage(corrected)` but before OCR, apply the filter:

  Current:
  ```swift
  let finalImage = rotatedImage(corrected)
  let observations = (try? await ocr.recognizeText(in: finalImage)) ?? []
  ```

  Change to:
  ```swift
  let rotated = rotatedImage(corrected)
  let finalImage = filterEngine.apply(filter, to: rotated) ?? rotated
  let observations = (try? await ocr.recognizeText(in: finalImage)) ?? []
  ```

  The rest of the apply flow (PDFAssembler + DocumentMutations + session.save) stays the same.

- [ ] **Step 5: Build**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner/DocumentScanner
  xcodebuild build -scheme DocumentScanner -destination 'id=B762C669-0A64-4665-8C00-10BD6628CBA2' 2>&1 | grep -E "warning:|error:|BUILD (SUCCEEDED|FAILED)" | grep -v "^ld:\|appintentsmetadataprocessor" | head -10
  ```

- [ ] **Step 6: Commit**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git add DocumentScanner/DocumentScanner/PageEditor/PageEditorView.swift
  git commit -m "Add filter picker to per-page editor

  Task 2 of plan-4b: segmented Picker below the rotation controls
  with Color / Greyscale / B&W / Photo options. The chosen filter
  is applied through the live displayed image so the user sees the
  effect as they tap. On Apply, the filter runs on the
  perspective-corrected + rotated image before OCR; re-OCR sees
  the final pixels so search text matches what the user actually
  sees (and B&W often OCRs better than color).

  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
  ```

## Task 3: Device smoke test

- [ ] **Step 1: Cmd+R to iPhone**

- [ ] **Step 2: Open per-page editor on an existing scan**
  - Open a document → Edit → tap a page → editor sheet appears.
  - Below the rotation controls: a segmented picker with Color / Greyscale / B&W / Photo. Default is Color.

- [ ] **Step 3: Try each filter**
  - Tap Greyscale → image goes to monochrome tones, color disappears.
  - Tap B&W → image becomes high-contrast monochrome (more punch than Greyscale).
  - Tap Photo → contrast and saturation bump.
  - Tap Color → original image returns.

- [ ] **Step 4: Apply with a filter**
  - Pick B&W (the most visually different).
  - Tap Apply → spinner → sheet dismisses.
  - The edited page in the document viewer now shows the B&W version.
  - Library row thumbnail (after a moment) reflects the filtered page.
  - Open the file in Files.app → the page is rasterized with the B&W filter baked in.
  - Search for a word on that page → still finds it (re-OCR ran on the filtered image).

- [ ] **Step 5: Sanity — no regressions**
  - Other plans' features still work (scan, library, edit, app lock, search highlighting).

- [ ] **Step 6: Commit milestone**

  ```
  cd /Users/pjones/Desktop/mobileDocumentScanner
  git commit --allow-empty -m "Milestone: Plan 4b verified end-to-end on device"
  ```

---

## After Plan 4b

What lands:

- Four image-filter presets in the per-page editor with live preview.

What remains:

- **Plan 5** — XCUITest golden-path tests with mocked scanner.

## Self-review notes

- Scope: tightly bounded — one new enum + helper, one picker in one view, one extra line in `applyEdit`.
- Spec-deviation risk: minimal. The filter pipeline is additive.
- Test coverage: 4 unit tests for ImageFilterEngine (dimensions per filter). Visual results verified by device smoke test.
- Risk: CIPhotoEffectNoir's contrast may be too aggressive for some documents; if so, swap to CIColorMonochrome with tuned intensity in a follow-up.
- Follow-ups: "Apply filter to all pages" button (one-tap document-wide filter), initial scan-time filter pick (in NameDocumentSheet), continuous brightness/contrast sliders for power users.

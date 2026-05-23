import XCTest
import PDFKit
@testable import DocumentScanner

@MainActor
final class DocumentSessionStripHighlightsTests: XCTestCase {

    func test_save_stripsHighlightAnnotations() throws {
        // The strip removes ALL .highlight-subtype annotations because PDFKit
        // doesn't reliably preserve the userName tag we tried to use to
        // discriminate. Non-highlight annotations (e.g., free-text notes)
        // should still survive a save.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let pdf = try PDFAssembler().assemble(
            pages: [ScannedPage(image: image, observations: [])],
            createdAt: Date()
        )
        let page = try XCTUnwrap(pdf.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)

        // A free-text annotation (NOT a highlight) — should survive the strip.
        let freeTextAnnotation = PDFAnnotation(bounds: pageBounds, forType: .freeText, withProperties: nil)
        freeTextAnnotation.contents = "note that should survive"
        page.addAnnotation(freeTextAnnotation)

        let storage = DocumentStorage(documentsURL: tempDir)
        let initialURL = try storage.write(pdf, preferredName: "Test")

        let summary = DocumentSummary(url: initialURL, displayName: "Test",
                                      createdAt: Date(), pageCount: 1, ocrSnippet: "",
                                      isCorrupt: false)
        let session = try DocumentSession(summary: summary, storage: storage)

        // Add a highlight annotation to the session's in-memory PDF (mimics what
        // the viewer's search-highlight code does at runtime).
        let sessionPage = try XCTUnwrap(session.pdf.page(at: 0))
        let highlight = PDFAnnotation(bounds: pageBounds, forType: .highlight, withProperties: nil)
        sessionPage.addAnnotation(highlight)

        _ = try session.save()

        // Reload from disk: free-text survives, highlight is gone.
        let reloaded = try XCTUnwrap(PDFDocument(url: initialURL))
        let reloadedPage = try XCTUnwrap(reloaded.page(at: 0))
        let types = reloadedPage.annotations.map(\.type)
        // PDFAnnotation.type returns the bare subtype name, not the slash-prefixed
        // PDFAnnotationSubtype.rawValue form.
        XCTAssertTrue(types.contains("FreeText"),
                      "free-text annotation should survive, got types: \(types)")
        XCTAssertFalse(types.contains("Highlight"),
                       "highlight annotations should be stripped, got types: \(types)")
    }
}

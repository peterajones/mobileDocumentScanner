import XCTest
import PDFKit
@testable import DocumentScanner

@MainActor
final class DocumentSessionStripHighlightsTests: XCTestCase {

    func test_save_stripsSearchHighlightAnnotations() throws {
        // Build a PDF with both a user annotation and one of our search-highlight
        // annotations. After save, only the user annotation should remain on disk.
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

        // User annotation (untagged) — should survive.
        let userAnnotation = PDFAnnotation(bounds: pageBounds, forType: .highlight, withProperties: nil)
        userAnnotation.userName = "user-added"
        page.addAnnotation(userAnnotation)

        let storage = DocumentStorage(documentsURL: tempDir)
        let initialURL = try storage.write(pdf, preferredName: "Test")

        let summary = DocumentSummary(url: initialURL, displayName: "Test",
                                      createdAt: Date(), pageCount: 1, ocrSnippet: "",
                                      isCorrupt: false)
        let session = try DocumentSession(summary: summary, storage: storage)

        // Re-attach a search-highlight annotation to the session's in-memory PDF
        // (mimics what the viewer's highlight code does at runtime).
        let sessionPage = try XCTUnwrap(session.pdf.page(at: 0))
        let highlight = PDFAnnotation(bounds: pageBounds, forType: .highlight, withProperties: nil)
        highlight.userName = DocumentSession.searchHighlightAnnotationName
        sessionPage.addAnnotation(highlight)

        // Sanity: in-memory PDF has both kinds of annotation now.
        XCTAssertEqual(sessionPage.annotations.count, 2)

        _ = try session.save()

        // Reload from disk and check what survived.
        let reloaded = try XCTUnwrap(PDFDocument(url: initialURL))
        let reloadedPage = try XCTUnwrap(reloaded.page(at: 0))
        let usernames = reloadedPage.annotations.compactMap(\.userName)
        XCTAssertTrue(usernames.contains("user-added"))
        XCTAssertFalse(usernames.contains(DocumentSession.searchHighlightAnnotationName))
    }
}

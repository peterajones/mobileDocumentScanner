import XCTest
import PDFKit
@testable import DocumentScanner

@MainActor
final class LibraryStoreTests: XCTestCase {

    func test_summary_fromPDFURL_readsTitlePageCountAndText() throws {
        let url = try writeFixturePDF()
        let summary = try DocumentSummary.fromFile(at: url)
        XCTAssertEqual(summary.displayName, "Test Doc")
        XCTAssertEqual(summary.pageCount, 1)
        XCTAssertTrue(summary.ocrSnippet.localizedCaseInsensitiveContains("hello"))
    }

    func test_inMemoryStore_appendSortsNewestFirst() {
        let store = InMemoryLibraryStore()
        let one = DocumentSummary.stub(name: "A", date: .init(timeIntervalSince1970: 100))
        let two = DocumentSummary.stub(name: "B", date: .init(timeIntervalSince1970: 200))
        store.append(one)
        store.append(two)
        XCTAssertEqual(store.summaries.map(\.displayName), ["B", "A"]) // newest first
    }

    // MARK: - Helpers

    /// Produce a fixture PDF whose text appears in `pdf.string` — i.e. the same
    /// content-stream invisible-text technique PDFAssembler uses (not PDFAnnotation,
    /// which does NOT contribute to pdf.string).
    private func writeFixturePDF() throws -> URL {
        let image: UIImage = {
            UIGraphicsBeginImageContextWithOptions(CGSize(width: 100, height: 100), true, 1)
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
            let img = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return img
        }()
        let page = ScannedPage(image: image, recognizedStrings: ["hello world"])
        let pdf = try PDFAssembler().assemble(pages: [page], createdAt: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Test Doc.pdf")
        try? FileManager.default.removeItem(at: url)
        let data = try XCTUnwrap(pdf.dataRepresentation())
        try data.write(to: url)
        return url
    }
}

private extension DocumentSummary {
    static func stub(name: String, date: Date) -> DocumentSummary {
        DocumentSummary(
            url: URL(fileURLWithPath: "/tmp/\(name).pdf"),
            displayName: name,
            createdAt: date,
            pageCount: 1,
            ocrSnippet: ""
        )
    }
}

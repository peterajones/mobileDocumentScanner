import XCTest
import PDFKit
@testable import DocumentScanner

final class DocumentSummaryCorruptTests: XCTestCase {

    func test_fromFile_corruptPDF_returnsCorruptVariant() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID()).pdf")
        let garbage = Data("not actually a pdf".utf8)
        try garbage.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = DocumentSummary.fromFile(at: url)
        XCTAssertTrue(summary.isCorrupt)
        XCTAssertEqual(summary.displayName, url.deletingPathExtension().lastPathComponent)
    }

    func test_fromFile_realPDF_returnsHealthySummary() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let pdf = try PDFAssembler().assemble(
            pages: [ScannedPage(image: image, observations: [])],
            createdAt: Date()
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthy-\(UUID()).pdf")
        try XCTUnwrap(pdf.dataRepresentation()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = DocumentSummary.fromFile(at: url)
        XCTAssertFalse(summary.isCorrupt)
        XCTAssertEqual(summary.pageCount, 1)
    }
}

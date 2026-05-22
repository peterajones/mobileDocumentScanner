import XCTest
import PDFKit
import UIKit
@testable import DocumentScanner

final class PDFAssemblerTests: XCTestCase {

    func test_assemble_singlePage_producesPDFWithOnePage() throws {
        let image = whitePageImage()
        let page = ScannedPage(image: image, recognizedStrings: [])
        let pdf = try PDFAssembler().assemble(pages: [page], createdAt: Date())
        XCTAssertEqual(pdf.pageCount, 1)
    }

    func test_assemble_multiplePages_producesCorrectPageCount() throws {
        let image = whitePageImage()
        let pages = (0..<3).map { _ in ScannedPage(image: image, recognizedStrings: []) }
        let pdf = try PDFAssembler().assemble(pages: pages, createdAt: Date())
        XCTAssertEqual(pdf.pageCount, 3)
    }

    func test_assemble_embedsRecognizedTextSoStringIsSearchable() throws {
        let image = whitePageImage()
        let page = ScannedPage(
            image: image,
            recognizedStrings: ["The quick brown fox", "jumps over the lazy dog"]
        )
        let pdf = try PDFAssembler().assemble(pages: [page], createdAt: Date())
        let text = pdf.string ?? ""
        XCTAssertTrue(text.contains("quick brown fox"), "got: \(text)")
        XCTAssertTrue(text.contains("lazy dog"), "got: \(text)")
    }

    func test_assemble_setsCreatedAtMetadata() throws {
        let image = whitePageImage()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let pdf = try PDFAssembler().assemble(
            pages: [ScannedPage(image: image, recognizedStrings: [])],
            createdAt: date
        )
        let attrs = pdf.documentAttributes ?? [:]
        XCTAssertEqual(attrs[PDFDocumentAttribute.creationDateAttribute] as? Date, date)
    }

    // MARK: - Helpers

    private func whitePageImage() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 612, height: 792), true, 1)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 612, height: 792))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }
}

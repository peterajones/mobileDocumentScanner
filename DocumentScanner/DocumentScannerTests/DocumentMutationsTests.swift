import XCTest
import PDFKit
@testable import DocumentScanner

final class DocumentMutationsTests: XCTestCase {

    func test_reorder_movesPageToNewIndex() throws {
        let pdf = try threePagePDF()
        DocumentMutations.reorder(in: pdf, from: 0, to: 2)
        XCTAssertEqual(pageMarkers(pdf), ["B", "C", "A"])
    }

    func test_deletePage_removesPageAtIndex() throws {
        let pdf = try threePagePDF()
        DocumentMutations.deletePage(in: pdf, at: 1)
        XCTAssertEqual(pageMarkers(pdf), ["A", "C"])
    }

    func test_append_addsNewPagesToEnd() throws {
        let pdf = try threePagePDF()
        let extra = try singlePagePDF(marker: "D")
        DocumentMutations.append(extra, to: pdf)
        XCTAssertEqual(pageMarkers(pdf), ["A", "B", "C", "D"])
    }

    func test_replacePage_swapsThePageAtIndex() throws {
        let pdf = try threePagePDF()       // [A, B, C]
        let replacement = try singlePagePDF(marker: "X")
        DocumentMutations.replacePage(in: pdf, at: 1, with: replacement)
        XCTAssertEqual(pageMarkers(pdf), ["A", "X", "C"])
    }

    func test_deletePages_removesMultiplePagesAtOnce() throws {
        let pdf = try threePagePDF()       // [A, B, C]
        DocumentMutations.deletePages(in: pdf, at: [0, 2])
        XCTAssertEqual(pageMarkers(pdf), ["B"])
    }

    func test_deletePages_descendingOrderingDoesntCorruptIndices() throws {
        // Build [A, B, C, D, E], delete indices [0, 1, 3]. Expected result: [C, E].
        let pdf = PDFDocument()
        for marker in ["A", "B", "C", "D", "E"] {
            pdf.insert(try markedPage(marker), at: pdf.pageCount)
        }
        DocumentMutations.deletePages(in: pdf, at: [0, 1, 3])
        XCTAssertEqual(pageMarkers(pdf), ["C", "E"])
    }

    func test_deletePages_skipsOutOfRangeIndices() throws {
        let pdf = try threePagePDF()       // [A, B, C]
        DocumentMutations.deletePages(in: pdf, at: [1, 99, -1])
        XCTAssertEqual(pageMarkers(pdf), ["A", "C"])
    }

    func test_deletePages_emptySetIsNoOp() throws {
        let pdf = try threePagePDF()
        DocumentMutations.deletePages(in: pdf, at: [])
        XCTAssertEqual(pageMarkers(pdf), ["A", "B", "C"])
    }

    // MARK: - Helpers

    private func threePagePDF() throws -> PDFDocument {
        let pdf = PDFDocument()
        for marker in ["A", "B", "C"] {
            pdf.insert(try markedPage(marker), at: pdf.pageCount)
        }
        return pdf
    }

    private func singlePagePDF(marker: String) throws -> PDFDocument {
        let pdf = PDFDocument()
        pdf.insert(try markedPage(marker), at: 0)
        return pdf
    }

    /// Builds a PDFPage whose `string` contains the marker, by routing through
    /// PDFAssembler so the searchable-text mechanism is the same as production.
    private func markedPage(_ marker: String) throws -> PDFPage {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let assembled = try PDFAssembler().assemble(
            pages: [ScannedPage(
                image: image,
                observations: [OCRObservation(string: marker,
                                              boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05))]
            )],
            createdAt: Date()
        )
        return try XCTUnwrap(assembled.page(at: 0))
    }

    private func pageMarkers(_ pdf: PDFDocument) -> [String] {
        (0..<pdf.pageCount).compactMap { idx in
            pdf.page(at: idx)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

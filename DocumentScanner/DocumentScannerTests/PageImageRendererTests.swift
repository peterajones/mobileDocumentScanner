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
            pages: [ScannedPage(image: source, observations: [])],
            createdAt: Date()
        )
        let page = try XCTUnwrap(pdf.page(at: 0))
        let rendered = try XCTUnwrap(PageImageRenderer().image(from: page))
        XCTAssertEqual(rendered.size.width, 100, accuracy: 1)
        XCTAssertEqual(rendered.size.height, 100, accuracy: 1)
    }
}

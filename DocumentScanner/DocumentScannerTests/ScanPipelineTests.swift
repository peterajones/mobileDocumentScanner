import XCTest
import UIKit
import PDFKit
@testable import DocumentScanner

final class ScanPipelineTests: XCTestCase {

    func test_process_returnsPDFWithSamePageCount() async throws {
        let images = [whiteImage(), whiteImage(), whiteImage()]
        let pipeline = ScanPipeline(ocr: StubOCR(returning: []))
        let result = try await pipeline.process(images: images)
        XCTAssertEqual(result.pdf.pageCount, 3)
    }

    func test_process_failsGracefully_whenOCRFailsForOnePage() async throws {
        let images = [whiteImage(), whiteImage()]
        let pipeline = ScanPipeline(ocr: FailingOnceOCR())
        let result = try await pipeline.process(images: images)
        XCTAssertEqual(result.pdf.pageCount, 2,
                       "page should be included even if OCR fails")
    }

    func test_process_returnsConcatenatedOCRText() async throws {
        let images = [whiteImage(), whiteImage()]
        let pipeline = ScanPipeline(ocr: StubOCR(returning: ["hello", "world"]))
        let result = try await pipeline.process(images: images)
        XCTAssertTrue(result.ocrText.contains("hello"))
        XCTAssertTrue(result.ocrText.contains("world"))
    }

    // MARK: - Helpers

    private func whiteImage() -> UIImage {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 100, height: 100), true, 1)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    private struct StubOCR: OCRProviding {
        let strings: [String]
        init(returning strings: [String]) { self.strings = strings }
        func recognizeText(in image: UIImage) async throws -> [String] { strings }
    }

    private struct FailingOnceOCR: OCRProviding {
        func recognizeText(in image: UIImage) async throws -> [String] {
            throw NSError(domain: "test", code: 1)
        }
    }
}

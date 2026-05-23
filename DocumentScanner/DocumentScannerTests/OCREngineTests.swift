import XCTest
import UIKit
@testable import DocumentScanner

final class OCREngineTests: XCTestCase {

    func test_recognizeText_emptyImage_returnsEmptyArray() async throws {
        let image = UIImage.fromColor(.white, size: CGSize(width: 100, height: 100))
        let engine = OCREngine()
        let observations = try await engine.recognizeText(in: image)
        XCTAssertTrue(observations.isEmpty)
    }

    func test_recognizeText_imageWithText_returnsRecognizedStrings() async throws {
        let image = UIImage.renderingText("Hello World", size: CGSize(width: 800, height: 200))
        let engine = OCREngine()
        let observations = try await engine.recognizeText(in: image)
        let joined = observations.map(\.string).joined(separator: " ")
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("hello"),
                      "expected to recognize 'hello' in \(observations.map(\.string))")
        // Each observation should have a real bounding box on the image.
        XCTAssertTrue(observations.allSatisfy { $0.boundingBox.width > 0 && $0.boundingBox.height > 0 })
    }
}

private extension UIImage {
    static func fromColor(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }

    static func renderingText(_ text: String, size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 96),
            .foregroundColor: UIColor.black
        ]
        (text as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: attrs)
        let img = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return img
    }
}

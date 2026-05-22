import UIKit

struct ScannedPage {
    let image: UIImage
    /// Lines of OCR-recognized text in document reading order. Passed in by the OCR engine.
    let recognizedStrings: [String]
}

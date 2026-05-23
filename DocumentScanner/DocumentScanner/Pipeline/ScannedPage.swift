import UIKit

struct ScannedPage {
    let image: UIImage
    /// OCR observations in document reading order. Each carries the recognized
    /// string and its bounding box on the source image (Vision-normalized,
    /// origin bottom-left). PDFAssembler uses the bounding boxes to position
    /// the invisible text layer so that search highlights align with the
    /// visible scan content.
    let observations: [OCRObservation]
}

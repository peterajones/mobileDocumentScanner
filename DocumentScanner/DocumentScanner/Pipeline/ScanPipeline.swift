import UIKit
import PDFKit

struct ScanResult {
    let pdf: PDFDocument
    let ocrText: String
}

/// Orchestrates OCR + PDF assembly. Implemented as an actor so concurrent calls
/// (rare but possible if the user kicks off two scans quickly) are serialized.
actor ScanPipeline {
    private let ocr: OCRProviding
    private let assembler: PDFAssembler

    init(ocr: OCRProviding = OCREngine(), assembler: PDFAssembler = PDFAssembler()) {
        self.ocr = ocr
        self.assembler = assembler
    }

    func process(images: [UIImage], createdAt: Date = .init()) async throws -> ScanResult {
        var pages: [ScannedPage] = []
        pages.reserveCapacity(images.count)

        for image in images {
            let strings: [String]
            do {
                strings = try await ocr.recognizeText(in: image)
            } catch {
                // Per spec: a failed OCR on one page does not block the document.
                strings = []
            }
            pages.append(ScannedPage(image: image, recognizedStrings: strings))
        }

        let pdf = try assembler.assemble(pages: pages, createdAt: createdAt)
        let ocrText = pages
            .flatMap(\.recognizedStrings)
            .joined(separator: "\n")
        return ScanResult(pdf: pdf, ocrText: ocrText)
    }
}

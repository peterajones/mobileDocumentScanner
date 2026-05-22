import UIKit
import PDFKit
import OSLog

/// The combined output of a scan pipeline run.
struct ScanResult {
    /// Searchable PDF assembled from the input page images. Caller writes this
    /// to disk via `DocumentStorage`.
    let pdf: PDFDocument
    /// All OCR-recognized text across pages, joined with newlines in input order.
    /// Used to populate `DocumentSummary.ocrSnippet` for library search.
    let ocrText: String
}

/// Orchestrates OCR + PDF assembly. Implemented as an actor so concurrent calls
/// (rare but possible if the user kicks off two scans quickly) are serialized.
actor ScanPipeline {
    private let ocr: OCRProviding
    private let assembler: PDFAssembler
    private let logger = Logger(subsystem: "ca.peter-jones.DocumentScanner", category: "Pipeline")

    init(ocr: OCRProviding = OCREngine(), assembler: PDFAssembler = PDFAssembler()) {
        self.ocr = ocr
        self.assembler = assembler
    }

    /// Run OCR on each image and assemble the results into a searchable PDF.
    ///
    /// Pages are processed serially because Vision saturates the Neural Engine per
    /// request; a `TaskGroup` would mostly contend for the same hardware.
    ///
    /// - Throws: only errors from `PDFAssembler.assemble`. Per-page OCR failures
    ///   are logged and absorbed — that page is still included in the PDF, but
    ///   without a text layer.
    func process(images: [UIImage], createdAt: Date = .init()) async throws -> ScanResult {
        var pages: [ScannedPage] = []
        pages.reserveCapacity(images.count)

        for (index, image) in images.enumerated() {
            let strings: [String]
            do {
                strings = try await ocr.recognizeText(in: image)
            } catch {
                logger.error("OCR failed on page \(index + 1, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

import CoreGraphics
import PDFKit
import UIKit

enum PDFAssemblerError: Error {
    case pageCreationFailed
    case documentLoadFailed
}

struct PDFAssembler {

    func assemble(pages: [ScannedPage], createdAt: Date) throws -> PDFDocument {
        // Render each scanned page into a PDF page via UIGraphicsPDFRenderer so that
        // any OCR text is part of the page content stream — that's what PDFKit's
        // `PDFDocument.string` extracts, and what other PDF readers index for search.
        // Drawing a transparent-coloured glyph on top of the image keeps the visual
        // page looking like the scan while making the text selectable/searchable.
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw PDFAssemblerError.pageCreationFailed
        }

        // Use US Letter as a sane default; each page's actual bounds come from its image.
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)

        // Embed metadata directly in the PDF byte stream via auxiliaryInfo so it
        // survives a write of the underlying bytes — mutating `documentAttributes`
        // on the parsed `PDFDocument` would only affect the in-memory object.
        //
        // CoreGraphics on iOS does not expose `kCGPDFContextCreationDate` or
        // `kCGPDFContextProducer` as Swift constants, but the dictionary string
        // keys CG actually looks for (verified at runtime) are "CGPDFContextDate"
        // for the creation date and "CGPDFContextProducer" for the producer.
        let auxiliaryInfo: CFDictionary = [
            "CGPDFContextDate": createdAt,
            "CGPDFContextProducer": "DocumentScanner",
        ] as CFDictionary

        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, auxiliaryInfo) else {
            throw PDFAssemblerError.pageCreationFailed
        }

        for page in pages {
            try renderPage(page, into: context)
        }

        context.closePDF()

        guard let document = PDFDocument(data: data as Data) else {
            throw PDFAssemblerError.documentLoadFailed
        }

        return document
    }

    private func renderPage(_ page: ScannedPage, into context: CGContext) throws {
        // VisionKit returns UIImages with a non-`.up` orientation flag (the camera
        // sensor is landscape; portrait photos carry a "rotate 90°" hint). Pulling
        // `.cgImage` returns the raw sensor-orientation pixels, losing that flag —
        // which lands the page rotated in the PDF. Normalize first so the bytes
        // we draw match what the user saw in the scanner.
        guard let cgImage = normalizedCGImage(from: page.image) else {
            throw PDFAssemblerError.pageCreationFailed
        }

        // Page size in points matches the image's pixel size at 1pt-per-pixel; this
        // preserves aspect ratio without resampling.
        let size = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        var pageRect = CGRect(origin: .zero, size: size)

        context.beginPage(mediaBox: &pageRect)

        // CGContext for PDF uses bottom-left origin. `draw(_:in:)` already handles
        // that and renders the image right-side up — an explicit y-flip here would
        // render it upside-down.
        context.draw(cgImage, in: pageRect)

        // Draw OCR-recognized text invisibly so `pdf.string` returns it and search
        // highlights align with the visible content. We use the PDF text-rendering
        // mode "invisible" (3), which keeps the glyphs in the content stream — and
        // therefore in the text extraction — while not painting any pixels. Each
        // observation is positioned at its Vision-normalized bounding box scaled to
        // page coordinates, so per-line highlights match the underlying text.
        if !page.observations.isEmpty {
            drawInvisibleText(page.observations, in: pageRect, into: context)
        }

        context.endPage()
    }

    /// Returns a CGImage whose pixel data matches what the UIImage displays —
    /// i.e. with the imageOrientation baked in — and whose pixel dimensions
    /// equal the UIImage's point size. Forcing scale=1 here is what keeps the
    /// resulting PDF page sized in document points rather than screen pixels;
    /// `renderPage` derives the page mediaBox from these dimensions.
    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(at: .zero)
        }.cgImage
    }

    private func drawInvisibleText(_ observations: [OCRObservation], in pageRect: CGRect, into context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)

        for observation in observations {
            // Vision returns normalized coords (0…1, origin bottom-left, y-up).
            // CGContext PDF coords are also origin bottom-left, y-up — no flip needed.
            let bbox = observation.boundingBox
            let rect = CGRect(
                x: bbox.origin.x * pageRect.width,
                y: bbox.origin.y * pageRect.height,
                width: bbox.width * pageRect.width,
                height: bbox.height * pageRect.height
            )
            guard rect.height > 0, rect.width > 0 else { continue }

            // Size the font so the rendered glyphs roughly match the observed
            // line height. Width-fit is approximate; PDFKit's findString uses
            // the glyph bounding boxes returned from this draw to position
            // highlights, so close-enough is good enough.
            let font = UIFont.systemFont(ofSize: rect.height)
            let attributed = NSAttributedString(
                string: observation.string,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.clear,
                ]
            )
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: rect.origin.x, y: rect.origin.y)
            CTLineDraw(ctLine, context)
        }

        context.restoreGState()
    }
}

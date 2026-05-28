import Foundation
import PDFKit

/// Pure helpers that mutate a `PDFDocument` in place. No disk I/O.
/// Save the document via `DocumentStorage.write(_:replacing:withName:)` after.
enum DocumentMutations {

    static func reorder(in pdf: PDFDocument, from: Int, to: Int) {
        guard from != to, let page = pdf.page(at: from) else { return }
        pdf.removePage(at: from)
        let clampedTo = min(to, pdf.pageCount)
        pdf.insert(page, at: clampedTo)
    }

    static func deletePage(in pdf: PDFDocument, at index: Int) {
        guard index >= 0, index < pdf.pageCount else { return }
        pdf.removePage(at: index)
    }

    /// Bulk-delete the pages at the given indices. Deletes in descending
    /// order so an earlier removal doesn't shift the meaning of later indices.
    /// Out-of-range entries are skipped.
    static func deletePages(in pdf: PDFDocument, at indices: Set<Int>) {
        for index in indices.sorted(by: >) {
            guard index >= 0, index < pdf.pageCount else { continue }
            pdf.removePage(at: index)
        }
    }

    /// Append all pages from `other` onto `pdf`. Used by "Add Pages" after the
    /// new scans run through ScanPipeline -> PDFAssembler.
    static func append(_ other: PDFDocument, to pdf: PDFDocument) {
        for i in 0..<other.pageCount {
            guard let page = other.page(at: i) else { continue }
            pdf.insert(page, at: pdf.pageCount)
        }
    }

    /// Replace the page at `index` in `pdf` with the first page of `replacement`.
    /// No-op if either bound is invalid.
    static func replacePage(in pdf: PDFDocument, at index: Int, with replacement: PDFDocument) {
        guard index >= 0, index < pdf.pageCount,
              let newPage = replacement.page(at: 0) else { return }
        pdf.removePage(at: index)
        pdf.insert(newPage, at: index)
    }
}

import SwiftUI
import PDFKit

struct DocumentRow: View {
    let summary: DocumentSummary

    var body: some View {
        HStack(spacing: 12) {
            if summary.isCorrupt {
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray6))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 56)
            } else {
                ThumbnailView(url: summary.url)
                    .frame(width: 44, height: 56)
                    .background(Color(.systemGray6))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray4)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(formattedSubtitle)
                    .font(.footnote)
                    .foregroundStyle(summary.isCorrupt ? .orange : .secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var formattedSubtitle: String {
        if summary.isCorrupt { return "Couldn't read this file" }
        let date = summary.createdAt.formatted(date: .abbreviated, time: .omitted)
        let pages = summary.pageCount == 1 ? "1 page" : "\(summary.pageCount) pages"
        return "\(date) · \(pages)"
    }
}

private struct ThumbnailView: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = await Self.render(url: url)
        }
    }

    private static func render(url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { return nil }
            let size = CGSize(width: 88, height: 112)
            return page.thumbnail(of: size, for: .mediaBox)
        }.value
    }
}

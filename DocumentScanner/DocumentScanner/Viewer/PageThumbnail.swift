import SwiftUI
import PDFKit

struct PageThumbnail: View {
    let page: PDFPage
    let size: CGSize

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray6))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray4)))
        .task(id: ObjectIdentifier(page)) {
            image = await Self.render(page: page, size: size)
        }
    }

    private static func render(page: PDFPage, size: CGSize) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            page.thumbnail(of: size, for: .mediaBox)
        }.value
    }
}

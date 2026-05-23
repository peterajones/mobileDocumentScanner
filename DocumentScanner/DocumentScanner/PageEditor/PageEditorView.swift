import SwiftUI
import PDFKit
import UIKit

/// Full-screen sheet for editing a single page's crop and rotation.
/// Mutates the passed-in DocumentSession on Apply and saves.
struct PageEditorView: View {
    @Bindable var session: DocumentSession
    let pageIndex: Int
    let onDismiss: () -> Void

    private let renderer = PageImageRenderer()
    private let segmenter = DocumentSegmenter()
    private let corrector = PerspectiveCorrector()
    private let ocr = OCREngine()

    @State private var pageImage: UIImage?
    @State private var quad: Quad?
    @State private var rotationQuarterTurns = 0  // 0/1/2/3 → 0°/90°/180°/270° CW
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let pageImage, let quadBinding {
                    VStack(spacing: 8) {
                        QuadOverlay(image: rotatedImage(pageImage), quad: quadBinding)
                            .padding()
                        rotationControls
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red).font(.footnote)
                        }
                    }
                } else {
                    ProgressView("Preparing page…")
                }
            }
            .navigationTitle("Edit Page \(pageIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }.disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Apply") { Task { await applyEdit() } }
                            .disabled(quad == nil)
                    }
                }
            }
            .task { await prepare() }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private var quadBinding: Binding<Quad>? {
        guard quad != nil else { return nil }
        return Binding(
            get: { quad ?? Quad.fullRect(in: pageImage?.size ?? .zero) },
            set: { quad = $0 }
        )
    }

    private var rotationControls: some View {
        HStack(spacing: 24) {
            Button {
                rotationQuarterTurns = (rotationQuarterTurns + 3) % 4   // counter-clockwise
            } label: {
                Image(systemName: "rotate.left").font(.title2)
            }
            Text("Rotation: \(rotationQuarterTurns * 90)°").font(.footnote).monospaced()
            Button {
                rotationQuarterTurns = (rotationQuarterTurns + 1) % 4   // clockwise
            } label: {
                Image(systemName: "rotate.right").font(.title2)
            }
        }
        .padding(.bottom, 16)
    }

    private func prepare() async {
        guard let page = session.pdf.page(at: pageIndex),
              let rendered = renderer.image(from: page) else {
            errorMessage = "Couldn't render page \(pageIndex + 1)."
            return
        }
        pageImage = rendered
        quad = (try? await segmenter.detect(in: rendered)) ?? Quad.fullRect(in: rendered.size)
    }

    private func rotatedImage(_ image: UIImage) -> UIImage {
        guard rotationQuarterTurns != 0 else { return image }
        // Apply rotation to the displayed image only. The actual quad still
        // operates in the underlying image's coordinate space; the apply
        // step rotates the corrected output, not the source.
        let angle = CGFloat(rotationQuarterTurns) * .pi / 2
        let size: CGSize = (rotationQuarterTurns % 2 == 0)
            ? image.size
            : CGSize(width: image.size.height, height: image.size.width)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: angle)
            image.draw(in: CGRect(x: -image.size.width / 2,
                                  y: -image.size.height / 2,
                                  width: image.size.width,
                                  height: image.size.height))
        }
    }

    private func applyEdit() async {
        guard let pageImage, let quad else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let corrected = corrector.correct(pageImage, quad: quad) else {
                errorMessage = "Couldn't apply crop."
                return
            }
            let finalImage = rotatedImage(corrected)
            let observations = (try? await ocr.recognizeText(in: finalImage)) ?? []
            let newDoc = try PDFAssembler().assemble(
                pages: [ScannedPage(image: finalImage, observations: observations)],
                createdAt: Date()
            )
            DocumentMutations.replacePage(in: session.pdf, at: pageIndex, with: newDoc)
            _ = try session.save()
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

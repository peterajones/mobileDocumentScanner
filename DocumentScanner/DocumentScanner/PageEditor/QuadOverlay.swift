import SwiftUI

struct QuadOverlay: View {
    let image: UIImage
    @Binding var quad: Quad

    var body: some View {
        GeometryReader { geo in
            let imageSize = image.size
            let viewSize = geo.size
            let scale = min(viewSize.width / imageSize.width,
                            viewSize.height / imageSize.height)
            let displayedSize = CGSize(width: imageSize.width * scale,
                                       height: imageSize.height * scale)
            let offsetX = (viewSize.width - displayedSize.width) / 2
            let offsetY = (viewSize.height - displayedSize.height) / 2

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()

                // Quad outline.
                Path { path in
                    let pts = quad.corners.map { p in
                        CGPoint(x: offsetX + p.x * scale,
                                y: offsetY + p.y * scale)
                    }
                    path.move(to: pts[0])
                    path.addLine(to: pts[1])
                    path.addLine(to: pts[2])
                    path.addLine(to: pts[3])
                    path.closeSubpath()
                }
                .stroke(Color.accentColor, lineWidth: 2)

                // 4 corner handles.
                handle(at: \.topLeft, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
                handle(at: \.topRight, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
                handle(at: \.bottomRight, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
                handle(at: \.bottomLeft, scale: scale, offset: CGPoint(x: offsetX, y: offsetY), imageSize: imageSize)
            }
        }
        .aspectRatio(image.size, contentMode: .fit)
    }

    @ViewBuilder
    private func handle(at corner: WritableKeyPath<Quad, CGPoint>,
                        scale: CGFloat,
                        offset: CGPoint,
                        imageSize: CGSize) -> some View {
        let point = quad[keyPath: corner]
        let screenPoint = CGPoint(x: offset.x + point.x * scale,
                                  y: offset.y + point.y * scale)

        Circle()
            .fill(Color.white)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .shadow(radius: 2)
            .position(screenPoint)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newScreenX = value.location.x
                        let newScreenY = value.location.y
                        let newImagePoint = CGPoint(
                            x: (newScreenX - offset.x) / scale,
                            y: (newScreenY - offset.y) / scale
                        )
                        var next = quad
                        next[keyPath: corner] = newImagePoint
                        quad = next.clamped(to: imageSize)
                    }
            )
    }
}

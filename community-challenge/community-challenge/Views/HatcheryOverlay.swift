import SwiftUI

/// A hatchery quadrilateral with compact handles and 44 pt drag targets.
struct HatcheryOverlay: View {

    /// The quad in the overlay's local coordinate space.
    @Binding var quad: QuadPoints?

    var color: Color = .appGreenPrimary
    var isEditable: Bool = true

    private let handleRadius: CGFloat = 4.52
    private let hitSize: CGFloat = 44

    private let space = "hatcheryOverlay"

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let current = quad ?? .defaultShape(in: size)

            ZStack {
                quadShape(current)
                    .fill(color.opacity(0.30))
                quadShape(current)
                    .stroke(color, lineWidth: 2)

                ForEach(QuadPoints.Corner.allCases, id: \.self) { corner in
                    handle(for: corner, in: size)
                        .position(current[corner])
                        .allowsHitTesting(isEditable)
                }
            }
            .coordinateSpace(.named(space))
            .onAppear {
                if quad == nil { quad = .defaultShape(in: size) }
            }
        }
    }

    private func quadShape(_ q: QuadPoints) -> Path {
        var path = Path()
        path.move(to: q.topLeft)
        path.addLine(to: q.topRight)
        path.addLine(to: q.bottomRight)
        path.addLine(to: q.bottomLeft)
        path.closeSubpath()
        return path
    }

    private func handle(for corner: QuadPoints.Corner, in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: handleRadius * 2, height: handleRadius * 2)
        }
        .frame(width: hitSize, height: hitSize)   // enlarged touch target
        .contentShape(Circle())
        .gesture(
            DragGesture(coordinateSpace: .named(space))
                .onChanged { value in
                    guard isEditable else { return }
                    let base = quad ?? .defaultShape(in: size)
                    let clamped = QuadPoints.clamp(value.location, in: size, margin: handleRadius)
                    let candidate = base.withCorner(corner, at: clamped)
                    // Reject moves that would self-intersect or collapse.
                    if candidate.isValid() {
                        quad = candidate
                    }
                }
        )
    }
}

#Preview {
    ZStack {
        Color.black
        StatefulPreviewWrapper()
    }
    .ignoresSafeArea()
}

/// Small helper so the binding-based overlay can be previewed interactively.
private struct StatefulPreviewWrapper: View {
    @State private var quad: QuadPoints?
    var body: some View {
        HatcheryOverlay(quad: $quad)
    }
}

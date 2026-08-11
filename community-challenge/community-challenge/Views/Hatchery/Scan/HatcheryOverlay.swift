import SwiftUI

/// Phase 2 — the draggable hatchery quadrilateral overlay.
///
/// Renders a green semi-transparent quad with four independently draggable
/// corner handles on top of the camera preview (or, later, the captured
/// image). Corners are kept inside the container and prevented from forming a
/// self-intersecting shape.
struct HatcheryOverlay: View {

    /// The quad in the overlay's local coordinate space. `nil` until the first
    /// layout pass, at which point it is seeded with a default perspective
    /// trapezoid sized to the container.
    @Binding var quad: QuadPoints?

    var color: Color = .appGreenPrimary
    var isEditable: Bool = true

    /// Visual radius of a handle; the touch target is larger (see `hitSize`).
    private let handleRadius: CGFloat = 11
    private let hitSize: CGFloat = 44

    /// Stable coordinate space for drags, so handle positions don't feed back
    /// into the reported drag location (which caused corners to fly around).
    private let space = "hatcheryOverlay"

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let current = quad ?? .defaultShape(in: size)

            ZStack {
                // Fill + outline
                quadShape(current)
                    .fill(color.opacity(0.25))
                quadShape(current)
                    .stroke(color, lineWidth: 2)

                // Draggable corner handles
                if isEditable {
                    ForEach(QuadPoints.Corner.allCases, id: \.self) { corner in
                        handle(for: corner, in: size)
                            .position(current[corner])
                    }
                }
            }
            .coordinateSpace(.named(space))
            .onAppear {
                if quad == nil { quad = .defaultShape(in: size) }
            }
        }
    }

    // MARK: - Shape

    private func quadShape(_ q: QuadPoints) -> Path {
        var path = Path()
        path.move(to: q.topLeft)
        path.addLine(to: q.topRight)
        path.addLine(to: q.bottomRight)
        path.addLine(to: q.bottomLeft)
        path.closeSubpath()
        return path
    }

    // MARK: - Handle

    private func handle(for corner: QuadPoints.Corner, in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: handleRadius * 2, height: handleRadius * 2)
            Circle()
                .stroke(Color.white, lineWidth: 3)
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

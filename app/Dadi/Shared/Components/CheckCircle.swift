import SwiftUI

/// The round checkbox: an empty ring that fills sage and draws its check in 0.32 s when the task is done.
struct CheckCircle: View {
    let done: Bool

    var body: some View {
        ZStack {
            Circle().fill(done ? Color.sageDeep : .clear)
            Circle().strokeBorder(done ? Color.sageDeep : .inkFaint, lineWidth: 1.5)
            CheckStroke()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(Color.bone, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(6)
        }
        .frame(width: 22, height: 22)
        .animation(.easeOut(duration: 0.32), value: done)
        .accessibilityHidden(true)
    }
}

/// A check mark path, drawn by trimming it.
struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.85))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.18))
        return path
    }
}

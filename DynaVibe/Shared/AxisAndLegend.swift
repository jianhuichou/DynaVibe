public enum Axis: String, CaseIterable, Identifiable {
    case x
    case y
    case z

    public var id: String { self.rawValue }
}

import SwiftUI

// MARK: - Common graph background

private struct GraphGridBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Grid lines
            Path { path in
                for i in 0...6 {               // horizontal
                    let y = CGFloat(i) * h / 6
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
                for i in 0...6 {               // vertical
                    let x = CGFloat(i) * w / 6
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
            }
            .stroke(Color.secondary.opacity(0.30),
                    style: StrokeStyle(lineWidth: 0.5, dash: [4]))

            // Border
            Rectangle()
                .stroke(Color.secondary, lineWidth: 0.8)
        }
    }
}

// Adaptive tick formatter for y-ticks
private func formatTick(_ v: Double) -> String {
    let a = abs(v)
    if a >= 100 { return String(Int(v)) }
    if a >= 10  { return String(format: "%.1f", v) }
    return String(format: "%.2f", v)
}

// This file only holds graph utilities such as the grid background and tick formatter.
// The LineGraphView and related previews have been removed as they are duplicated elsewhere.

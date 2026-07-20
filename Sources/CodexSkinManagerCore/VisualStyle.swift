import SwiftUI

package enum VisualStyle {
    package static let abyss = Color(red: 0.025, green: 0.055, blue: 0.10)
    package static let deepBlue = Color(red: 0.035, green: 0.15, blue: 0.26)
    package static let selection = Color(red: 0.27, green: 0.78, blue: 1.0)
    package static let success = Color(red: 0.28, green: 0.92, blue: 0.73)
    package static let warning = Color(red: 1.0, green: 0.66, blue: 0.24)
    package static let panelStrong = Color(red: 0.04, green: 0.075, blue: 0.12).opacity(0.96)
    package static let panelQuiet = Color(red: 0.045, green: 0.085, blue: 0.14).opacity(0.74)
    package static let ice = selection
    package static let frost = Color(red: 0.66, green: 0.92, blue: 1.0)
    package static let jade = success
    package static let panel = panelStrong
    package static let muted = Color.white.opacity(0.62)
}

package struct WeaponPlateShape: Shape {
    package init() {}

    package func path(in rect: CGRect) -> Path {
        let small = min(18, rect.width * 0.08)
        let large = min(42, rect.width * 0.16)
        var path = Path()
        path.move(to: CGPoint(x: small, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - large, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: large * 0.72))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - small))
        path.addLine(to: CGPoint(x: rect.maxX - small, y: rect.maxY))
        path.addLine(to: CGPoint(x: large, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - large * 0.72))
        path.addLine(to: CGPoint(x: 0, y: small))
        path.closeSubpath()
        return path
    }
}

package struct MangaBurstBackground: View {
    package init() {}

    package var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [VisualStyle.abyss, VisualStyle.deepBlue, VisualStyle.abyss],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Canvas { context, size in
                    let origin = CGPoint(x: size.width * 0.76, y: size.height * 0.18)
                    for index in 0..<18 {
                        let angle = Double(index) / 18 * Double.pi * 2
                        let radius = max(size.width, size.height) * 1.15
                        var ray = Path()
                        ray.move(to: origin)
                        ray.addLine(to: CGPoint(
                            x: origin.x + cos(angle) * radius,
                            y: origin.y + sin(angle) * radius
                        ))
                        context.stroke(
                            ray,
                            with: .color(index.isMultiple(of: 3) ? VisualStyle.selection.opacity(0.07) : .white.opacity(0.02)),
                            lineWidth: index.isMultiple(of: 3) ? 1.2 : 0.6
                        )
                    }
                }
                LinearGradient(
                    colors: [.clear, VisualStyle.ice.opacity(0.08), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

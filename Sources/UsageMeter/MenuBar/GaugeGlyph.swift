import SwiftUI

/// The custom menu-bar gauge mark — a monochrome, vector version of the app
/// icon's gauge (a smooth open-bottom arc + a needle on a small pivot). Drawn
/// with `Canvas` so it scales crisply at any menu-bar size and tints to any
/// color (usage level / service status), matching the app icon's identity.
///
/// Geometry is kept 1:1 with the icon renderer (`Scripts/icon/render.swift`,
/// the `gaugefill` glyph) so the menu bar and the app icon read as the same mark.
struct GaugeGlyph: View {
    /// The tint to draw with (usage color / status color / primary).
    var tint: Color

    /// Needle value 0...1 (defaults to ~68% to echo the app icon). Could be
    /// driven by the live session % in the future.
    var value: Double = 0.68

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let cx = size.width / 2
            let cy = size.height * 0.59             // optical centering (arc is top-heavy)
            let r = s * 0.38
            let shading = GraphicsContext.Shading.color(tint)

            func pt(_ deg: Double, _ rad: Double) -> CGPoint {
                let a = deg * .pi / 180
                return CGPoint(x: cx + rad * cos(a), y: cy - rad * sin(a))   // screen y is down
            }

            // Open-bottom gauge arc (210° → −30°), smooth, round-capped.
            var arc = Path()
            let steps = 72
            for i in 0...steps {
                let p = pt(210 - 240 * Double(i) / Double(steps), r)
                if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
            }
            ctx.stroke(arc, with: shading,
                       style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round, lineJoin: .round))

            // Needle to the value, anchored on a small pivot hub.
            let end = 210 - 240 * value
            let a = end * .pi / 180
            let dir = CGVector(dx: cos(a), dy: -sin(a))
            let perp = CGVector(dx: -dir.dy, dy: dir.dx)
            let bw = s * 0.09
            let c = CGPoint(x: cx, y: cy)
            func add(_ v: CGVector, _ k: CGFloat) -> CGPoint { CGPoint(x: c.x + v.dx * k, y: c.y + v.dy * k) }
            var needle = Path()
            needle.move(to: CGPoint(x: c.x + perp.dx * bw / 2, y: c.y + perp.dy * bw / 2))
            needle.addLine(to: add(dir, r * 0.66))                                  // tip
            needle.addLine(to: CGPoint(x: c.x - perp.dx * bw / 2, y: c.y - perp.dy * bw / 2))
            needle.addLine(to: add(dir, -r * 0.16))                                 // back tail
            needle.closeSubpath()
            ctx.fill(needle, with: shading)

            // Pivot hub.
            let hr = s * 0.052
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: 2 * hr, height: 2 * hr)), with: shading)
        }
        .accessibilityHidden(true)
    }
}

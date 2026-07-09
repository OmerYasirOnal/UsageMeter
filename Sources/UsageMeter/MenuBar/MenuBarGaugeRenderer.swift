import AppKit
import UsageMeterKit

/// Renders the menu-bar gauge as a template image: a low-alpha ring track plus
/// a full-alpha arc filled to `percent`, starting at 12 o'clock and sweeping
/// clockwise. Template images are alpha-only masks — AppKit/SwiftUI recolor
/// them via `.foregroundStyle`, the same mechanism that tinted the SF Symbol
/// glyph this replaces (see `MenuBarLabel.tint`).
///
/// A live SwiftUI `Canvas` does NOT render inside a `MenuBarExtra` label —
/// AppKit snapshots the label to a template image and `Canvas` draws blank
/// (documented in docs/STATUS.md). That's why this is pre-rendered to an
/// `NSImage` instead of drawn live.
enum MenuBarGaugeRenderer {
    /// `percent == nil` (logged out / local-only, no session metric) draws just
    /// the empty track — the same "neutral, no claim" meaning the old SF Symbol
    /// glyph had with no live account data.
    static func render(percent: Double?, pointSize: CGFloat = 16) -> NSImage {
        let scale: CGFloat = 2
        let px = Int(pointSize * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            draw(in: ctx, px: CGFloat(px), percent: percent)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func draw(in ctx: CGContext, px: CGFloat, percent: Double?) {
        let center = CGPoint(x: px / 2, y: px / 2)
        let radius = px * 0.36
        ctx.setLineWidth(px * 0.14)
        ctx.setLineCap(.round)

        // Full track, low alpha.
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.28))
        ctx.addPath(arcPath(center: center, radius: radius, startDeg: 90, endDeg: 90 - 360))
        ctx.strokePath()

        guard let percent else { return }
        let fraction = GaugeGeometry.fillFraction(percent: percent)
        guard fraction > 0 else { return }

        // Filled arc, full alpha, starting at 12 o'clock (90°), sweeping
        // clockwise as `fraction` grows (decreasing angle in this
        // math-convention, non-flipped coordinate space).
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(arcPath(center: center, radius: radius, startDeg: 90, endDeg: 90 - fraction * 360))
        ctx.strokePath()
    }

    /// Samples an arc as a path by linear angle interpolation — sidesteps
    /// CGContext.addArc's easily-inverted `clockwise` flag, which is what
    /// caused this arc to sweep the wrong way originally. Degrees, math
    /// convention (0 = +x/3 o'clock, 90 = +y/12 o'clock, increasing =
    /// counterclockwise) — mirrors Scripts/icon/render.swift's `arcPath`.
    private static func arcPath(center: CGPoint, radius: CGFloat, startDeg: Double, endDeg: Double) -> CGPath {
        let path = CGMutablePath()
        let steps = 120
        for i in 0...steps {
            let deg = startDeg + (endDeg - startDeg) * Double(i) / Double(steps)
            let rad = deg * .pi / 180
            let point = CGPoint(x: center.x + radius * CGFloat(cos(rad)), y: center.y + radius * CGFloat(sin(rad)))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

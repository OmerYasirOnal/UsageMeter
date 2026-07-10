import AppKit
import UsageMeterKit

/// Renders the menu-bar gauge: a faint full-ring track plus a `fillColor` arc
/// filled to `percent`, starting at 12 o'clock and sweeping clockwise.
///
/// Unlike the template (alpha-only) image this replaced, the result is a
/// **colored, non-template** image so the fill keeps its purple instead of being
/// recolored monochrome by the menu-bar tint. It's built with an
/// appearance-adaptive drawing handler and stroked with `NSColor` set methods, so
/// both the track and the fill resolve against the *menu bar's* effective
/// appearance at draw time — the menu bar can be dark even when the app is in
/// light mode, and a bitmap baked for the app's appearance would read wrong there.
///
/// A live SwiftUI `Canvas` does NOT render inside a `MenuBarExtra` label —
/// AppKit snapshots the label and `Canvas` draws blank (documented in
/// docs/STATUS.md). That's why this is pre-rendered to an `NSImage`.
enum MenuBarGaugeRenderer {
    /// `percent == nil` (logged out / local-only, no session metric) draws just
    /// the empty track — the same "neutral, no claim" meaning the old glyph had
    /// with no live account data. `fillColor` is then unused.
    static func render(percent: Double?, fillColor: NSColor, pointSize: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            draw(in: rect, percent: percent, fillColor: fillColor)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(in rect: NSRect, percent: Double?, fillColor: NSColor) {
        let px = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = px * 0.36
        let lineWidth = px * 0.14

        // Full track, faint. A fixed mid-gray (not a dynamic label color) on
        // purpose: a colored status-item image isn't reliably re-resolved in the
        // menu bar's own (often dark-vibrant) appearance, so an appearance-keyed
        // gray can come out low-contrast. Mid-gray at low alpha reads on a light
        // OR dark menu bar.
        let track = arcPath(center: center, radius: radius, startDeg: 90, endDeg: 90 - 360)
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        NSColor(white: 0.55, alpha: 0.4).setStroke()
        track.stroke()

        guard let percent else { return }
        let fraction = GaugeGeometry.fillFraction(percent: percent)
        guard fraction > 0 else { return }

        // Filled arc, starting at 12 o'clock (90°), sweeping clockwise as
        // `fraction` grows (decreasing angle in this math-convention,
        // non-flipped coordinate space).
        let fill = arcPath(center: center, radius: radius, startDeg: 90, endDeg: 90 - fraction * 360)
        fill.lineWidth = lineWidth
        fill.lineCapStyle = .round
        fillColor.setStroke()
        fill.stroke()
    }

    /// Samples an arc as a path by linear angle interpolation — sidesteps
    /// `NSBezierPath.appendArc`'s easily-inverted direction flag, which is what
    /// caused this arc to sweep the wrong way originally. Degrees, math
    /// convention (0 = +x/3 o'clock, 90 = +y/12 o'clock, increasing =
    /// counterclockwise) — mirrors Scripts/icon/render.swift's `arcPath`.
    private static func arcPath(center: CGPoint, radius: CGFloat, startDeg: Double, endDeg: Double) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 120
        for i in 0...steps {
            let deg = startDeg + (endDeg - startDeg) * Double(i) / Double(steps)
            let rad = deg * .pi / 180
            let point = CGPoint(x: center.x + radius * CGFloat(cos(rad)), y: center.y + radius * CGFloat(sin(rad)))
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        return path
    }
}

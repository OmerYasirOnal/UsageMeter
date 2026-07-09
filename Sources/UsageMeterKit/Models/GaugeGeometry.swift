import Foundation

/// Pure percent → fill-fraction math for the menu-bar gauge glyph. Kept
/// AppKit-free so it's testable like the rest of UsageMeterKit; the actual
/// CoreGraphics drawing lives in the app target's `MenuBarGaugeRenderer`.
public enum GaugeGeometry {
    /// Clamps `percent` to 0...100 and returns the fraction (0...1) of the ring
    /// that should be filled.
    public static func fillFraction(percent: Double) -> Double {
        min(100, max(0, percent)) / 100.0
    }
}

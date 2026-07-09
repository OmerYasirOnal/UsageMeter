import Testing
@testable import UsageMeterKit

@Suite struct GaugeGeometryTests {
    @Test func zeroPercentHasNoFill() {
        #expect(GaugeGeometry.fillFraction(percent: 0) == 0)
    }

    @Test func fiftyPercentIsHalfFilled() {
        #expect(GaugeGeometry.fillFraction(percent: 50) == 0.5)
    }

    @Test func hundredPercentIsFullyFilled() {
        #expect(GaugeGeometry.fillFraction(percent: 100) == 1.0)
    }

    @Test func clampsBelowZero() {
        #expect(GaugeGeometry.fillFraction(percent: -20) == 0)
    }

    @Test func clampsAboveHundred() {
        #expect(GaugeGeometry.fillFraction(percent: 150) == 1.0)
    }
}

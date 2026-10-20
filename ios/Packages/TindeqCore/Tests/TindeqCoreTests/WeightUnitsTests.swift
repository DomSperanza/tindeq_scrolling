import XCTest
@testable import TindeqCore

final class WeightUnitsTests: XCTestCase {
    func testRoundTrip() {
        let kg: Float = 7.3
        let lbs = WeightUnits.kgToDisplay(kg, .lbs)
        XCTAssertEqual(WeightUnits.displayToKg(lbs, .lbs), kg, accuracy: 0.0001)
        XCTAssertEqual(WeightUnits.kgToDisplay(kg, .kg), kg)
    }

    func testFormat() {
        XCTAssertEqual(WeightUnits.format(2, .kg), "2.0 kg")
        XCTAssertEqual(WeightUnits.format(2, .lbs), "4.4 lbs")
    }

    func testSnap() {
        XCTAssertEqual(WeightUnits.snapToStep(4.41), 4.5)
        XCTAssertEqual(WeightUnits.snapToStep(4.2), 4.0)
    }

    func testNormalizedKeepsGap() {
        let s = GateSettings(minPullKg: 5, scrollPullKg: 4).normalized()
        XCTAssertEqual(s.scrollPullKg, 5.5)
        let ok = GateSettings(minPullKg: 2, scrollPullKg: 8).normalized()
        XCTAssertEqual(ok.scrollPullKg, 8)
    }

    func testSettingsCodableRoundTrip() throws {
        let s = GateSettings(minPullKg: 3, scrollPullKg: 9, weightUnit: .kg, handsFreeOnly: true, blockedAction: .endSession)
        let decoded = try JSONDecoder().decode(GateSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}

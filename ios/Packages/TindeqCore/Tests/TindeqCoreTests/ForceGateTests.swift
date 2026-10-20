import XCTest
@testable import TindeqCore

final class ForceGateTests: XCTestCase {
    private func makeGate(min: Float = 2, scroll: Float = 8) -> ForceGate {
        ForceGate(settings: GateSettings(minPullKg: min, scrollPullKg: scroll))
    }

    func testHoldingAtOrAboveMin() {
        var gate = makeGate()
        XCTAssertEqual(gate.process(weightKg: 2, now: 0).mode, .holding)
        XCTAssertEqual(gate.process(weightKg: 5, now: 0.1).mode, .holding)
    }

    func testWarningThenBlockedAfterGrace() {
        var gate = makeGate()
        let first = gate.process(weightKg: 0, now: 10)
        XCTAssertEqual(first.mode, .warning)
        XCTAssertEqual(first.graceRemaining, 3, accuracy: 0.0001)

        let mid = gate.process(weightKg: 0, now: 11.5)
        XCTAssertEqual(mid.mode, .warning)
        XCTAssertEqual(mid.graceRemaining, 1.5, accuracy: 0.0001)

        let blocked = gate.process(weightKg: 0, now: 13)
        XCTAssertEqual(blocked.mode, .blocked)
        XCTAssertEqual(blocked.graceRemaining, 0)
    }

    func testPullingBackToMinClearsGrace() {
        var gate = makeGate()
        _ = gate.process(weightKg: 0, now: 0)
        _ = gate.process(weightKg: 0, now: 2.9)
        XCTAssertEqual(gate.process(weightKg: 3, now: 3).mode, .holding)
        // Grace restarts from scratch on the next dip.
        XCTAssertEqual(gate.process(weightKg: 0, now: 4).mode, .warning)
        XCTAssertEqual(gate.process(weightKg: 0, now: 6.9).mode, .warning)
        XCTAssertEqual(gate.process(weightKg: 0, now: 7).mode, .blocked)
    }

    func testBlockedUnlocksImmediatelyAtMin() {
        var gate = makeGate()
        _ = gate.process(weightKg: 0, now: 0)
        XCTAssertEqual(gate.process(weightKg: 0, now: 5).mode, .blocked)
        XCTAssertEqual(gate.process(weightKg: 2, now: 5.01).mode, .holding)
    }

    func testScrollFiresOncePerSpike() {
        var gate = makeGate()
        XCTAssertFalse(gate.process(weightKg: 4, now: 0).scrollTriggered)
        XCTAssertTrue(gate.process(weightKg: 8.5, now: 1).scrollTriggered)
        // Staying above the threshold does not fire again.
        XCTAssertFalse(gate.process(weightKg: 9, now: 2).scrollTriggered)
        XCTAssertFalse(gate.process(weightKg: 8.2, now: 3).scrollTriggered)
    }

    func testScrollRearmsBelowRatio() {
        var gate = makeGate()
        XCTAssertTrue(gate.process(weightKg: 8, now: 0).scrollTriggered)
        // 7 kg is above 85% of 8 (6.8), so still disarmed.
        XCTAssertFalse(gate.process(weightKg: 7, now: 1).scrollArmed)
        XCTAssertFalse(gate.process(weightKg: 8, now: 2).scrollTriggered)
        // Drop below 6.8 re-arms.
        XCTAssertTrue(gate.process(weightKg: 6, now: 3).scrollArmed)
        XCTAssertTrue(gate.process(weightKg: 8, now: 4).scrollTriggered)
    }

    func testScrollCooldown() {
        var gate = makeGate()
        XCTAssertTrue(gate.process(weightKg: 8, now: 0).scrollTriggered)
        _ = gate.process(weightKg: 3, now: 0.2)
        // Re-armed, but still inside the 600 ms cooldown.
        XCTAssertFalse(gate.process(weightKg: 8, now: 0.5).scrollTriggered)
        _ = gate.process(weightKg: 3, now: 0.55)
        XCTAssertTrue(gate.process(weightKg: 8, now: 0.7).scrollTriggered)
    }

    func testNoScrollUnlessHolding() {
        // Scroll threshold below min pull can't fire while in warning.
        var gate = ForceGate(settings: GateSettings(minPullKg: 10, scrollPullKg: 5))
        XCTAssertFalse(gate.process(weightKg: 6, now: 0).scrollTriggered)
    }

    func testResetClearsGrace() {
        var gate = makeGate()
        _ = gate.process(weightKg: 0, now: 0)
        gate.reset()
        let out = gate.process(weightKg: 0, now: 10)
        XCTAssertEqual(out.mode, .warning)
        XCTAssertEqual(out.graceRemaining, 3, accuracy: 0.0001)
    }
}

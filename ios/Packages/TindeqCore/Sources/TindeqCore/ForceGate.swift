import Foundation

public enum GateMode: String, Sendable {
    case idle
    case holding
    case warning
    case blocked
}

public struct GateOutput: Equatable, Sendable {
    public var mode: GateMode
    public var graceRemaining: TimeInterval
    public var scrollArmed: Bool
    /// True on the single sample where a scroll spike fired.
    public var scrollTriggered: Bool
}

/// Force gate state machine. Same rules as `ForceGateController` on Android:
/// - at/above min pull → holding
/// - below min pull → warning for `graceDuration`, then blocked
/// - while holding, a spike to scroll pull fires one scroll, then re-arms once
///   force drops below `rearmRatio` of scroll pull (with a cooldown between scrolls)
///
/// Time is passed in so the logic is deterministic under test.
public struct ForceGate: Sendable {
    public static let graceDuration: TimeInterval = 3.0
    public static let scrollCooldown: TimeInterval = 0.6
    public static let rearmRatio: Float = 0.85

    public var settings: GateSettings

    private var scrollArmed = true
    private var lastScrollAt: TimeInterval = -.infinity
    private var belowMinSince: TimeInterval?

    public init(settings: GateSettings) {
        self.settings = settings
    }

    /// Clears grace/scroll state, e.g. on disconnect or when a session starts.
    public mutating func reset() {
        scrollArmed = true
        belowMinSince = nil
    }

    public mutating func process(weightKg: Float, now: TimeInterval) -> GateOutput {
        let mode: GateMode
        let graceRemaining: TimeInterval

        if weightKg >= settings.minPullKg {
            belowMinSince = nil
            mode = .holding
            graceRemaining = 0
        } else {
            let since = belowMinSince ?? now
            belowMinSince = since
            let elapsed = now - since
            graceRemaining = max(0, Self.graceDuration - elapsed)
            mode = elapsed >= Self.graceDuration ? .blocked : .warning
        }

        var triggered = false
        if mode == .holding,
           scrollArmed,
           weightKg >= settings.scrollPullKg,
           now - lastScrollAt > Self.scrollCooldown {
            scrollArmed = false
            lastScrollAt = now
            triggered = true
        }

        if weightKg < settings.scrollPullKg * Self.rearmRatio {
            scrollArmed = true
        }

        return GateOutput(
            mode: mode,
            graceRemaining: graceRemaining,
            scrollArmed: scrollArmed,
            scrollTriggered: triggered
        )
    }
}

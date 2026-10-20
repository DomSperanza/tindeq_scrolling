import Foundation

/// What happens once the user stays below min pull past the grace period.
/// iOS can't close Instagram or send the user home, so these replace Android's
/// "close Instagram when blocked" toggle.
public enum BlockedAction: String, CaseIterable, Codable, Sendable {
    /// Pause video and cover the feed; pulling back to min unlocks it.
    case lockFeed
    /// Leave the reels session and return to the home screen.
    case endSession
}

public struct GateSettings: Codable, Equatable, Sendable {
    public var minPullKg: Float
    public var scrollPullKg: Float
    public var weightUnit: WeightUnit
    public var handsFreeOnly: Bool
    public var blockedAction: BlockedAction

    public init(
        minPullKg: Float = 2,
        scrollPullKg: Float = 8,
        weightUnit: WeightUnit = .lbs,
        handsFreeOnly: Bool = false,
        blockedAction: BlockedAction = .lockFeed
    ) {
        self.minPullKg = minPullKg
        self.scrollPullKg = scrollPullKg
        self.weightUnit = weightUnit
        self.handsFreeOnly = handsFreeOnly
        self.blockedAction = blockedAction
    }

    /// Keeps scroll pull at least `WeightUnits.minGapKg` above min pull, like the
    /// Android settings screen does.
    public func normalized() -> GateSettings {
        var copy = self
        copy.minPullKg = max(0, copy.minPullKg)
        let floor = copy.minPullKg + WeightUnits.minGapKg
        if copy.scrollPullKg < floor {
            copy.scrollPullKg = floor
        }
        return copy
    }
}

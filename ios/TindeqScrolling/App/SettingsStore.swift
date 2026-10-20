import Foundation
import TindeqCore

/// Persists `GateSettings` in UserDefaults (the iOS counterpart of Android's
/// SharedPreferences-backed `SettingsRepository`).
struct SettingsStore {
    private static let key = "gate_settings_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GateSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(GateSettings.self, from: data) else {
            return GateSettings()
        }
        return settings.normalized()
    }

    func save(_ settings: GateSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

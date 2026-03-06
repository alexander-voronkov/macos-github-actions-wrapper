import Foundation

final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let key = "runnertray.settings"

    func load() -> RunnerSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(RunnerSettings.self, from: data) else {
            return RunnerSettings()
        }
        return settings
    }

    func save(_ settings: RunnerSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}

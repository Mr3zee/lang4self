import Foundation

@MainActor
protocol LMStudioSettingsStoring: AnyObject {
    func load() -> LMStudioSettings
    func save(_ settings: LMStudioSettings)
}

@MainActor
final class UserDefaultsLMStudioSettingsStore: LMStudioSettingsStoring {
    private static let key = "lmStudioSentenceSettings"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> LMStudioSettings {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(LMStudioSettings.self, from: data)
        else { return .defaults }
        return decoded.sanitized
    }

    func save(_ settings: LMStudioSettings) {
        guard let data = try? JSONEncoder().encode(settings.sanitized) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

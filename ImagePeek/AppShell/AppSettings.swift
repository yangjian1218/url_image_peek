import Foundation

struct ImagePeekSettings: Codable, Equatable {
    var automaticPreview = true
    var launchAtLogin = false
    var imageColumn: Int?
}

struct ImageColumnFilter: Equatable {
    let column: Int?
    static let all = ImageColumnFilter(column: nil)

    func includes(column: Int?) -> Bool {
        self.column == nil || self.column == column
    }
}

final class SettingsStore {
    private let userDefaults: UserDefaults
    private let key = "imagePeek.settings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> ImagePeekSettings {
        guard let data = userDefaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ImagePeekSettings.self, from: data) else {
            return ImagePeekSettings()
        }
        return settings
    }

    func save(_ settings: ImagePeekSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: key)
    }
}

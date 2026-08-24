import Foundation
import ServiceManagement

struct ImagePeekSettings: Codable, Equatable {
    var automaticPreview = true
    var launchAtLogin = false
    var imageColumn: Int?
    var wpsClipboardFallback = true
}

struct ImageColumnFilter: Equatable {
    let column: Int?
    static let all = ImageColumnFilter(column: nil)

    func includes(column: Int?) -> Bool {
        self.column == nil || self.column == column
    }
}

enum ImageColumnInput {
    static func column(from text: String) -> Int? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let column = Int(trimmedText),
              column > 0 else {
            return nil
        }
        return column
    }

    static func text(for column: Int?) -> String {
        column.map(String.init) ?? ""
    }
}

protocol LaunchAtLoginServicing {
    func setEnabled(_ enabled: Bool) throws
}

struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

final class LaunchAtLoginController {
    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing = SystemLaunchAtLoginService()) {
        self.service = service
    }

    func apply(enabled: Bool) -> Bool {
        do {
            try service.setEnabled(enabled)
            return true
        } catch {
            return false
        }
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

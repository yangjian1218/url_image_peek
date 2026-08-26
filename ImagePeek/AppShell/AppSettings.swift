import Foundation
import ServiceManagement
import Combine

struct ImagePeekSettings: Codable, Equatable {
    var automaticPreview = true
    var launchAtLogin = false
    var imageColumn: Int?
    var wpsClipboardFallback = true
    var showsPixelDimensions = true
    var showsLoadSource = false
    var globalSelectionPreviewEnabled = false
    var cacheSizeGiB = 1
    var cacheRetentionDays = 30

    var cachePolicy: CachePolicy {
        let boundedGiB = min(max(cacheSizeGiB, 1), 10)
        let boundedDays = min(max(cacheRetentionDays, 1), 365)
        return CachePolicy(
            byteLimit: boundedGiB * CachePolicy.bytesPerGiB,
            maximumAge: TimeInterval(boundedDays * 24 * 60 * 60)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case automaticPreview
        case launchAtLogin
        case imageColumn
        case wpsClipboardFallback
        case showsPixelDimensions
        case showsLoadSource
        case globalSelectionPreviewEnabled
        case cacheSizeGiB
        case cacheRetentionDays
    }

    init(
        automaticPreview: Bool = true,
        launchAtLogin: Bool = false,
        imageColumn: Int? = nil,
        wpsClipboardFallback: Bool = true,
        showsPixelDimensions: Bool = true,
        showsLoadSource: Bool = false,
        globalSelectionPreviewEnabled: Bool = false,
        cacheSizeGiB: Int = 1,
        cacheRetentionDays: Int = 30
    ) {
        self.automaticPreview = automaticPreview
        self.launchAtLogin = launchAtLogin
        self.imageColumn = imageColumn
        self.wpsClipboardFallback = wpsClipboardFallback
        self.showsPixelDimensions = showsPixelDimensions
        self.showsLoadSource = showsLoadSource
        self.globalSelectionPreviewEnabled = globalSelectionPreviewEnabled
        self.cacheSizeGiB = cacheSizeGiB
        self.cacheRetentionDays = cacheRetentionDays
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        automaticPreview = try container.decodeIfPresent(Bool.self, forKey: .automaticPreview) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        imageColumn = try container.decodeIfPresent(Int.self, forKey: .imageColumn)
        wpsClipboardFallback = try container.decodeIfPresent(Bool.self, forKey: .wpsClipboardFallback) ?? true
        showsPixelDimensions = try container.decodeIfPresent(Bool.self, forKey: .showsPixelDimensions) ?? true
        showsLoadSource = try container.decodeIfPresent(Bool.self, forKey: .showsLoadSource) ?? false
        globalSelectionPreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalSelectionPreviewEnabled) ?? false
        cacheSizeGiB = try container.decodeIfPresent(Int.self, forKey: .cacheSizeGiB) ?? 1
        cacheRetentionDays = try container.decodeIfPresent(Int.self, forKey: .cacheRetentionDays) ?? 30
    }
}

struct CachePolicy: Equatable, Sendable {
    static let bytesPerGiB = 1_073_741_824
    static let defaultMaximumAge: TimeInterval = 30 * 24 * 60 * 60

    let byteLimit: Int
    let maximumAge: TimeInterval
}

enum RuntimeDiagnosticResult: Equatable, Sendable {
    case success(source: ImageLoadSource, elapsed: TimeInterval)
    case localSuccess
    case failure
    case cancelled
}

struct RuntimeDiagnosticsSnapshot: Equatable, Sendable {
    var networkLoadCount = 0
    var diskCacheHitCount = 0
    var memoryCacheHitCount = 0
    var localLoadCount = 0
    var failureCount = 0
    var lastResult: RuntimeDiagnosticResult?
}

struct RuntimeDiagnostics: Sendable {
    private(set) var snapshot = RuntimeDiagnosticsSnapshot()

    mutating func record(_ result: RuntimeDiagnosticResult) {
        snapshot.lastResult = result
        switch result {
        case let .success(source, _):
            switch source {
            case .network:
                snapshot.networkLoadCount += 1
            case .diskCache:
                snapshot.diskCacheHitCount += 1
            case .memoryCache:
                snapshot.memoryCacheHitCount += 1
            }
        case .localSuccess:
            snapshot.localLoadCount += 1
        case .failure:
            snapshot.failureCount += 1
        case .cancelled:
            break
        }
    }
}

@MainActor
final class OperationsStatusStore: ObservableObject {
    @Published private(set) var diagnostics = RuntimeDiagnosticsSnapshot()
    @Published private(set) var cacheSummary: DiskCacheSummary?
    @Published private(set) var webSheetReadStatus = WebSheetReadStatus.idle
    @Published private(set) var globalSelectionReadStatus = GlobalSelectionReadStatus.idle
    @Published private(set) var globalSelectionAccessibilityDiagnostics = GlobalSelectionAccessibilityDiagnostics.empty

    func updateDiagnostics(_ value: RuntimeDiagnosticsSnapshot) {
        diagnostics = value
    }

    func updateCacheSummary(_ value: DiskCacheSummary?) {
        cacheSummary = value
    }

    func updateWebSheetReadStatus(_ value: WebSheetReadStatus) {
        webSheetReadStatus = value
    }

    func updateGlobalSelectionReadStatus(_ value: GlobalSelectionReadStatus) {
        globalSelectionReadStatus = value
    }

    func updateGlobalSelectionAccessibilityDiagnostics(_ value: GlobalSelectionAccessibilityDiagnostics) {
        globalSelectionAccessibilityDiagnostics = value
    }
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

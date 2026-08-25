import SwiftUI

struct SettingsView: View {
    let permissionManager: PermissionManager
    private let settingsStore: SettingsStore
    private let launchAtLoginController: LaunchAtLoginController
    @ObservedObject private var operationsStatusStore: OperationsStatusStore
    private let clearCache: () async -> Bool

    @State private var isAccessibilityGranted = false
    @State private var settings: ImagePeekSettings
    @State private var imageColumnText: String
    @State private var launchAtLoginError: String?
    @State private var isClearingCache = false
    @State private var cacheActionMessage: String?

    init(
        permissionManager: PermissionManager,
        settingsStore: SettingsStore,
        operationsStatusStore: OperationsStatusStore,
        clearCache: @escaping () async -> Bool,
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    ) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        _operationsStatusStore = ObservedObject(wrappedValue: operationsStatusStore)
        self.clearCache = clearCache
        self.launchAtLoginController = launchAtLoginController
        let settings = settingsStore.load()
        _settings = State(initialValue: settings)
        _imageColumnText = State(initialValue: ImageColumnInput.text(for: settings.imageColumn))
    }

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("App mode", value: "Menu bar")
                LabeledContent("Supported in this phase", value: "WPS, Microsoft Excel, Feishu Sheets in Chrome")
                Toggle("Automatic preview", isOn: $settings.automaticPreview)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section("Accessibility") {
                HStack {
                    Label(
                        isAccessibilityGranted ? "Permission granted" : "Permission required",
                        systemImage: isAccessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(isAccessibilityGranted ? .green : .orange)

                    Spacer()

                    if !isAccessibilityGranted {
                        Button("Grant Access") {
                            permissionManager.requestAccessibility()
                            refreshPermissionStatus()
                        }
                    }
                }

                Text("ImagePeek uses Accessibility to read the focused spreadsheet cell. Screen Recording is not required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Spreadsheet") {
                TextField("Image URL column (blank = all columns)", text: $imageColumnText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Use WPS clipboard fallback", isOn: $settings.wpsClipboardFallback)
                Text("WPS does not expose the selected cell text through Accessibility on this Mac. ImagePeek observes WPS selection changes and temporarily copies the cell value, then restores your clipboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                Toggle("Show pixel dimensions", isOn: $settings.showsPixelDimensions)
                Toggle("Show load source", isOn: $settings.showsLoadSource)
                Toggle("Preview selected image URL anywhere", isOn: $settings.globalSelectionPreviewEnabled)
                Text("After selecting a complete image URL, ImagePeek waits one second before previewing it. It works only where macOS Accessibility exposes selected text and never uses the clipboard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Cache") {
                TextField("Maximum cache size (GiB)", value: $settings.cacheSizeGiB, format: .number)
                TextField("Cache retention (days)", value: $settings.cacheRetentionDays, format: .number)
                Text("Changes to cache limits apply after the next app launch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LabeledContent("Current cache", value: cacheSummaryText)
                Button("Clear Cache") {
                    Task {
                        isClearingCache = true
                        cacheActionMessage = await clearCache() ? "Cache cleared." : "Cache could not be cleared."
                        isClearingCache = false
                    }
                }
                .disabled(isClearingCache)
                if let cacheActionMessage {
                    Text(cacheActionMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                let diagnostics = operationsStatusStore.diagnostics
                LabeledContent("Network loads", value: "\(diagnostics.networkLoadCount)")
                LabeledContent("Disk cache hits", value: "\(diagnostics.diskCacheHitCount)")
                LabeledContent("Memory cache hits", value: "\(diagnostics.memoryCacheHitCount)")
                LabeledContent("Local images", value: "\(diagnostics.localLoadCount)")
                LabeledContent("Failures", value: "\(diagnostics.failureCount)")
                LabeledContent("Feishu Sheets", value: operationsStatusStore.webSheetReadStatus.message)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 640)
        .onAppear(perform: refreshPermissionStatus)
        .onChange(of: imageColumnText) { text in
            settings.imageColumn = ImageColumnInput.column(from: text)
        }
        .onChange(of: settings.launchAtLogin) { enabled in
            guard !launchAtLoginController.apply(enabled: enabled) else {
                launchAtLoginError = nil
                return
            }
            settings.launchAtLogin = !enabled
            launchAtLoginError = "macOS could not update the login item."
        }
        .onChange(of: settings) { settingsStore.save($0) }
    }

    private func refreshPermissionStatus() {
        isAccessibilityGranted = permissionManager.isAccessibilityGranted
    }

    private var cacheSummaryText: String {
        guard let summary = operationsStatusStore.cacheSummary else { return "Unavailable" }
        return "\(summary.entryCount) items · \(ByteCountFormatter.string(fromByteCount: Int64(summary.byteCount), countStyle: .file))"
    }
}

import SwiftUI

struct SettingsView: View {
    let permissionManager: PermissionManager
    private let settingsStore: SettingsStore
    private let launchAtLoginController: LaunchAtLoginController

    @State private var isAccessibilityGranted = false
    @State private var settings: ImagePeekSettings
    @State private var imageColumnText: String
    @State private var launchAtLoginError: String?

    init(
        permissionManager: PermissionManager,
        settingsStore: SettingsStore,
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    ) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        self.launchAtLoginController = launchAtLoginController
        let settings = settingsStore.load()
        _settings = State(initialValue: settings)
        _imageColumnText = State(initialValue: ImageColumnInput.text(for: settings.imageColumn))
    }

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("App mode", value: "Menu bar")
                LabeledContent("Supported in this phase", value: "WPS, Microsoft Excel")
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
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 360)
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
}

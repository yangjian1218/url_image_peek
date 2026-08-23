import SwiftUI

struct SettingsView: View {
    let permissionManager: PermissionManager
    private let settingsStore: SettingsStore

    @State private var isAccessibilityGranted = false
    @State private var settings: ImagePeekSettings

    init(permissionManager: PermissionManager, settingsStore: SettingsStore) {
        self.permissionManager = permissionManager
        self.settingsStore = settingsStore
        _settings = State(initialValue: settingsStore.load())
    }

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("App mode", value: "Menu bar")
                LabeledContent("Supported in this phase", value: "WPS, Microsoft Excel")
                Toggle("Automatic preview", isOn: $settings.automaticPreview)
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
        .onChange(of: settings) { settingsStore.save($0) }
    }

    private func refreshPermissionStatus() {
        isAccessibilityGranted = permissionManager.isAccessibilityGranted
    }
}

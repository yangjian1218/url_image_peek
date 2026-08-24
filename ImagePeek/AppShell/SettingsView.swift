import SwiftUI

struct SettingsView: View {
    let permissionManager: PermissionManager
    private let settingsStore: SettingsStore

    @State private var isAccessibilityGranted = false
    @State private var isKeyboardShortcutAccessGranted = false
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

            Section("Keyboard shortcuts") {
                HStack {
                    Label(
                        isKeyboardShortcutAccessGranted ? "Permission granted" : "Input Monitoring required",
                        systemImage: isKeyboardShortcutAccessGranted ? "checkmark.circle.fill" : "keyboard.badge.ellipsis"
                    )
                    .foregroundStyle(isKeyboardShortcutAccessGranted ? .green : .orange)

                    Spacer()

                    if !isKeyboardShortcutAccessGranted {
                        Button("Enable Shortcuts") {
                            permissionManager.requestKeyboardShortcutAccess()
                        }
                    }
                }

                Text("Space, Esc, and Option shortcuts need Input Monitoring. ImagePeek only handles them while an ImagePeek preview is visible in WPS or Microsoft Excel.")
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
        .frame(minWidth: 520, minHeight: 430)
        .onAppear(perform: refreshPermissionStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
        }
        .onChange(of: settings) { settingsStore.save($0) }
    }

    private func refreshPermissionStatus() {
        isAccessibilityGranted = permissionManager.isAccessibilityGranted
        isKeyboardShortcutAccessGranted = permissionManager.isKeyboardShortcutAccessGranted
    }
}

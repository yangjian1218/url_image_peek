import SwiftUI

struct SettingsView: View {
    let permissionManager: PermissionManager

    @State private var isAccessibilityGranted = false

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("App mode", value: "Menu bar")
                LabeledContent("Supported in this phase", value: "WPS, Microsoft Excel")
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

            Section("First-round scope") {
                Text("When Accessibility exposes a focused WPS or Excel cell containing an image URL or local image path, ImagePeek shows a non-activating preview beside the cell. WPS clipboard fallback remains opt-in and is never used by background polling.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear(perform: refreshPermissionStatus)
    }

    private func refreshPermissionStatus() {
        isAccessibilityGranted = permissionManager.isAccessibilityGranted
    }
}

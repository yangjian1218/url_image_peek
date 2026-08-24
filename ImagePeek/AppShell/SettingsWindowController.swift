import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(permissionManager: PermissionManager, settingsStore: SettingsStore) {
        let rootView = SettingsView(permissionManager: permissionManager, settingsStore: settingsStore)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ImagePeek Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 360))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

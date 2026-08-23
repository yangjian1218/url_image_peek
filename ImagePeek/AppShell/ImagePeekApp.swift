import AppKit

@main
final class ImagePeekApp: NSObject, NSApplicationDelegate {
    private static let appDelegate = ImagePeekApp()
    private var menuBarController: MenuBarController?

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(permissionManager: PermissionManager())
    }
}

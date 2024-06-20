import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

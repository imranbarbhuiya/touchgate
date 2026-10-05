import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var gate: GateController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = GateController()
        gate = controller
        let menu = NSMenu()
        menu.addItem(withTitle: "Protected apps…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Lock now", action: #selector(lockNow), keyEquivalent: "l")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TouchGate…", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "TouchGate")
        status.menu = menu
        statusItem = status
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = menu.copy() as? NSMenu
        main.addItem(app)
        NSApp.mainMenu = main
        if controller.apps.isEmpty || CommandLine.arguments.contains("--settings") { showSettings() }
    }

    @objc func showSettings() {
        guard let gate else { return }
        gate.refreshTouchID()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 540), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "TouchGate"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(gate: gate))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func lockNow() { gate?.lockAll() }
    @objc func quit() { gate?.requestQuit() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}

@main
enum TouchGate {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

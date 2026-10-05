import AppKit
import SwiftUI
import LocalAuthentication
import ServiceManagement
import UniformTypeIdentifiers
import ApplicationServices
import TouchGateCore

struct ProtectedApp: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let path: String

    init?(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        self.id = id
        self.name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        self.path = url.path
    }
}

@MainActor
final class GateController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var apps: [ProtectedApp] = []
    @Published private(set) var gateApp: ProtectedApp?
    @Published private(set) var authenticating = false
    @Published var notice: String?
    @Published var gateNotice: String?
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var touchIDAvailable = false
    @Published private(set) var windowControlAvailable = AXIsProcessTrusted()
    @Published private(set) var windowsHidden = false
    private var state = LockState()
    private var context: LAContext?
    private var requestID: UUID?
    private var gateTarget: NSRunningApplication?
    private var gateWindow: NSWindow?
    private var minimizedWindows: [pid_t: [AXUIElement]] = [:]
    private var promptOnActivation = false
    private let lockerID = Bundle.main.bundleIdentifier ?? "io.github.imranbarbhuiya.touchgate"
    private let windowControlNotice = "Window control is needed to hide this app. Allow TouchGate in System Settings → Privacy & Security → Accessibility, then retry."

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "protectedApps"),
           let saved = try? JSONDecoder().decode([ProtectedApp].self, from: data) {
            apps = saved.filter { $0.id != lockerID && $0.id != "com.apple.finder" }
        }
        refreshTouchID()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemLocked), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemLocked), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        hideProtectedApps()
        if let app = NSWorkspace.shared.frontmostApplication { check(app) }
    }

    func refreshTouchID() {
        let probe = LAContext()
        touchIDAvailable = probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) && probe.biometryType == .touchID
        windowControlAvailable = AXIsProcessTrusted()
    }

    private func authenticate(reason: String, completion: @escaping (Bool, String?) -> Void) {
        guard context == nil else { return }
        let request = LAContext()
        request.localizedFallbackTitle = ""
        request.localizedCancelTitle = "Keep locked"
        request.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard request.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), request.biometryType == .touchID else {
            touchIDAvailable = false
            completion(false, "Touch ID is unavailable. Set it up or unlock your Mac with its password to re-enable biometrics, then retry.")
            return
        }
        touchIDAvailable = true
        context = request
        let id = UUID()
        requestID = id
        authenticating = true
        request.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            Task { @MainActor in
                guard let self, self.requestID == id else { return }
                self.context = nil
                self.requestID = nil
                self.authenticating = false
                let code = (error as? LAError)?.code
                let cancelled = code == .userCancel || code == .appCancel || code == .systemCancel
                completion(success, success || cancelled ? nil : "Touch ID did not unlock the app. Try again.")
            }
        }
    }

    private func cancelAuthentication() {
        let previous = context
        context = nil
        requestID = nil
        authenticating = false
        previous?.invalidate()
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        check(app)
    }

    private func check(_ app: NSRunningApplication) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        if app.bundleIdentifier == lockerID {
            requestAutomaticUnlock()
            return
        }
        if context != nil && app.activationPolicy != .regular { return }
        let protectedIDs = Set(apps.map(\.id))
        if state.requiresAuthentication(for: app.bundleIdentifier, protectedApps: protectedIDs, lockerID: lockerID),
           let record = apps.first(where: { $0.id == app.bundleIdentifier }) {
            if gateTarget?.processIdentifier != app.processIdentifier { cancelAuthentication() }
            gateTarget = app
            gateApp = record
            promptOnActivation = context == nil
            windowsHidden = hide(app)
            gateNotice = windowsHidden ? nil : windowControlNotice
            showGate()
        } else if gateTarget != nil && app.bundleIdentifier != gateTarget?.bundleIdentifier {
            cancelAuthentication()
        }
    }

    private func showGate() {
        if gateWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TouchGate"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: UnlockView(gate: self))
            window.center()
            gateWindow = window
        }
        NSApp.activate()
        gateWindow?.makeKeyAndOrderFront(nil)
        requestAutomaticUnlock()
    }

    private func requestAutomaticUnlock() {
        guard promptOnActivation, NSApp.isActive, gateWindow?.isKeyWindow == true, windowsHidden else { return }
        promptOnActivation = false
        unlockApp()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === gateWindow else { return }
        requestAutomaticUnlock()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === gateWindow { keepLocked() }
    }

    func unlockApp() {
        guard let target = gateTarget, let record = gateApp else { return }
        promptOnActivation = false
        windowsHidden = hide(target)
        guard windowsHidden else { gateNotice = windowControlNotice; return }
        gateNotice = nil
        authenticate(reason: "Unlock \(record.name)") { [weak self] success, message in
            guard let self, self.gateTarget?.processIdentifier == target.processIdentifier else { return }
            self.gateNotice = message
            guard success else { return }
            guard !target.isTerminated else { self.keepLocked(); return }
            self.state.unlock(record.id)
            self.gateWindow?.orderOut(nil)
            self.gateTarget = nil
            self.gateApp = nil
            self.restoreWindows(for: target.processIdentifier)
            target.unhide()
            NSApp.yieldActivation(to: target)
            target.activate(options: [])
        }
    }

    func keepLocked() {
        cancelAuthentication()
        promptOnActivation = false
        gateWindow?.orderOut(nil)
        gateTarget = nil
        gateApp = nil
    }

    func lockAll() {
        keepLocked()
        state.lock()
        hideProtectedApps()
    }

    private func hideProtectedApps() {
        let ids = Set(apps.map(\.id))
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier.map(ids.contains) == true {
            if !hide(app) { notice = "Some apps need window control. Allow TouchGate in System Settings → Privacy & Security → Accessibility." }
        }
    }

    private func hide(_ app: NSRunningApplication) -> Bool {
        if app.isHidden || app.hide() { return true }
        windowControlAvailable = AXIsProcessTrusted()
        guard windowControlAvailable else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        if AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success { return true }
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &result) == .success,
              let windows = result as? [AXUIElement], !windows.isEmpty else { return false }
        var succeeded = true
        for window in windows {
            var minimized: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
               minimized as? Bool == true { continue }
            if AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success {
                minimizedWindows[app.processIdentifier, default: []].append(window)
            } else { succeeded = false }
        }
        return succeeded
    }

    private func restoreWindows(for pid: pid_t) {
        for window in minimizedWindows.removeValue(forKey: pid) ?? [] {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
    }

    func requestWindowControl() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        windowControlAvailable = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func systemLocked(_ notification: Notification) { lockAll() }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == state.unlockedAppID { state.lock() }
        if app.processIdentifier == gateTarget?.processIdentifier { keepLocked() }
        minimizedWindows.removeValue(forKey: app.processIdentifier)
    }

    func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Protect apps"
        guard panel.runModal() == .OK else { return }
        let selected = panel.urls.compactMap(ProtectedApp.init).filter { $0.id != lockerID && $0.id != "com.apple.finder" }
        guard !selected.isEmpty else { notice = "Select an application other than Finder or TouchGate."; return }
        authenticate(reason: "Change your protected apps") { [weak self] success, message in
            guard let self else { return }
            self.notice = message
            guard success else { return }
            for app in selected where !self.apps.contains(where: { $0.id == app.id }) { self.apps.append(app) }
            self.apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.save()
            self.lockAll()
        }
    }

    func remove(_ app: ProtectedApp) {
        authenticate(reason: "Stop protecting \(app.name)") { [weak self] success, message in
            guard let self else { return }
            self.notice = message
            guard success else { return }
            self.apps.removeAll { $0.id == app.id }
            for target in NSWorkspace.shared.runningApplications where target.bundleIdentifier == app.id {
                self.restoreWindows(for: target.processIdentifier)
            }
            self.save()
            self.lockAll()
        }
    }

    private func save() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(apps), forKey: "protectedApps") }
        catch { notice = "Your protected app list could not be saved." }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        authenticate(reason: "Change TouchGate's login setting") { [weak self] success, message in
            guard let self else { return }
            self.notice = message
            guard success else { return }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                self.loginEnabled = SMAppService.mainApp.status == .enabled
                if enabled && !self.loginEnabled { self.notice = "Allow TouchGate in System Settings → General → Login Items." }
            } catch { self.notice = "The login setting could not be changed: \(error.localizedDescription)" }
        }
    }

    func requestQuit() {
        if apps.isEmpty { NSApp.terminate(nil); return }
        authenticate(reason: "Quit TouchGate and stop protecting your apps") { [weak self] success, message in
            self?.notice = message
            if success, let self {
                for pid in Array(self.minimizedWindows.keys) { self.restoreWindows(for: pid) }
                NSApp.terminate(nil)
            }
        }
    }
}

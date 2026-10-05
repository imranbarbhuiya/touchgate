import AppKit
import SwiftUI
import LocalAuthentication
import ServiceManagement
import UniformTypeIdentifiers
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
final class GateController: NSObject, ObservableObject {
    @Published private(set) var apps: [ProtectedApp] = []
    @Published private(set) var gateApp: ProtectedApp?
    @Published private(set) var authenticating = false
    @Published var notice: String?
    @Published var gateNotice: String?
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var touchIDAvailable = false
    private var state = LockState()
    private var context: LAContext?
    private var requestID: UUID?
    private var gateTarget: NSRunningApplication?
    private var gateWindow: NSWindow?
    private var redirectingToGate = false
    private let lockerID = Bundle.main.bundleIdentifier ?? "io.github.imranbarbhuiya.touchgate"

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
        if app.bundleIdentifier == lockerID { redirectingToGate = false; return }
        guard !redirectingToGate else { return }
        if context != nil && app.activationPolicy != .regular { return }
        let protectedIDs = Set(apps.map(\.id))
        if state.requiresAuthentication(for: app.bundleIdentifier, protectedApps: protectedIDs, lockerID: lockerID),
           let record = apps.first(where: { $0.id == app.bundleIdentifier }) {
            if gateTarget?.processIdentifier != app.processIdentifier { cancelAuthentication() }
            gateTarget = app
            gateApp = record
            redirectingToGate = true
            gateNotice = app.hide() ? nil : "This app could not be hidden. Keep its windows closed until you unlock it."
            showGate()
        } else if gateTarget != nil && app.bundleIdentifier != gateTarget?.bundleIdentifier {
            cancelAuthentication()
            gateWindow?.orderOut(nil)
            gateTarget = nil
            gateApp = nil
        }
    }

    private func showGate() {
        if gateWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TouchGate"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: UnlockView(gate: self))
            window.center()
            gateWindow = window
        }
        NSApp.activate()
        gateWindow?.makeKeyAndOrderFront(nil)
    }

    func unlockApp() {
        guard let target = gateTarget, let record = gateApp else { return }
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
            target.unhide()
            target.activate(options: [])
        }
    }

    func keepLocked() {
        cancelAuthentication()
        redirectingToGate = false
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
            app.hide()
        }
    }

    @objc private func systemLocked(_ notification: Notification) { lockAll() }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == state.unlockedAppID { state.lock() }
        if app.processIdentifier == gateTarget?.processIdentifier { keepLocked() }
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
            if success { NSApp.terminate(nil) }
        }
    }
}

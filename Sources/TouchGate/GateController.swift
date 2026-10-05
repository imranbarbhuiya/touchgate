import AppKit
import SwiftUI
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
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
final class GateController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var apps: [ProtectedApp] = []
    @Published private(set) var gateApp: ProtectedApp?
    @Published private(set) var authenticating = false
    @Published var notice: String?
    @Published var gateNotice: String?
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var touchIDAvailable = false
    @Published private(set) var windowsCovered = false
    @Published private(set) var lockMode = LockMode.everyActivation
    @Published private(set) var authenticationView: LAAuthenticationView?
    private var state = LockState()
    private var context: LAContext?
    private var requestID: UUID?
    private var pendingEvaluation: (() -> Void)?
    private var gateTarget: NSRunningApplication?
    private var gateWindow: NSWindow?
    private let coverageFailure = "Window positions are unavailable. Protected windows cannot be covered right now."
    private let covers = WindowCoverController()
    private var cancelledPIDs: Set<pid_t> = []
    private var promptOnActivation = false
    private var coverTimer: Timer?
    private let lockerID = Bundle.main.bundleIdentifier ?? "io.github.imranbarbhuiya.touchgate"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "protectedApps"),
           let saved = try? JSONDecoder().decode([ProtectedApp].self, from: data) {
            apps = saved.filter { $0.id != lockerID && $0.id != "com.apple.finder" }
        }
        lockMode = LockMode(rawValue: UserDefaults.standard.string(forKey: "lockMode") ?? "") ?? .everyActivation
        state = LockState(mode: lockMode)
        refreshTouchID()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemLocked), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemLocked), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(systemLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        covers.onUnlock = { [weak self] pid in
            guard let app = NSRunningApplication(processIdentifier: pid) else { return }
            self?.check(app, userInitiated: true)
        }
        refreshCovers()
        if let app = NSWorkspace.shared.frontmostApplication { check(app) }
    }

    func refreshTouchID() {
        let probe = LAContext()
        touchIDAvailable = probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) && probe.biometryType == .touchID
    }

    @objc private func appBecameActive(_ notification: Notification) {
        refreshTouchID()
        refreshCovers()
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
        let evaluate = { [weak self] in
            guard self?.requestID == id else { return }
            request.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
                Task { @MainActor in
                    guard let self, self.requestID == id else { return }
                    self.context = nil
                    self.requestID = nil
                    self.authenticationView = nil
                    self.authenticating = false
                    let code = (error as? LAError)?.code
                    let cancelled = code == .userCancel || code == .appCancel || code == .systemCancel
                    completion(success, success || cancelled ? nil : "Touch ID did not unlock the app. Try again.")
                }
            }
        }
        if gateTarget != nil {
            authenticationView = LAAuthenticationView(context: request, controlSize: .regular)
            pendingEvaluation = evaluate
            NSApp.activate(ignoringOtherApps: true)
            gateWindow?.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            evaluate()
        }
    }

    private func beginEmbeddedAuthentication() {
        guard let evaluate = pendingEvaluation else { return }
        guard NSApp.isActive, authenticationView?.window?.isKeyWindow == true else {
            NSApp.activate(ignoringOtherApps: true)
            gateWindow?.makeKeyAndOrderFront(nil)
            return
        }
        pendingEvaluation = nil
        evaluate()
    }

    private func cancelAuthentication() {
        let previous = context
        context = nil
        requestID = nil
        pendingEvaluation = nil
        authenticationView = nil
        authenticating = false
        previous?.invalidate()
    }

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
        check(app)
    }

    private func check(_ app: NSRunningApplication, userInitiated: Bool = false) {
        if app.bundleIdentifier == lockerID {
            refreshTouchID()
            requestAutomaticUnlock()
            return
        }
        if userInitiated { cancelledPIDs.remove(app.processIdentifier) }
        if gateTarget != nil {
            if apps.contains(where: { $0.id == app.bundleIdentifier }) {
                if userInitiated, gateTarget?.processIdentifier == app.processIdentifier, context == nil {
                    promptOnActivation = true
                }
                showGate()
            }
            return
        }
        if cancelledPIDs.contains(app.processIdentifier) { refreshCovers(); return }
        if context != nil { return }
        let protectedIDs = Set(apps.map(\.id))
        if state.requiresAuthentication(for: app.bundleIdentifier, processID: app.processIdentifier, protectedApps: protectedIDs, lockerID: lockerID),
           let record = apps.first(where: { $0.id == app.bundleIdentifier }) {
            gateTarget = app
            gateApp = record
            promptOnActivation = true
            refreshCovers()
            showGate()
        } else {
            refreshCovers()
        }
    }

    func showGate() {
        if gateWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TouchGate"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: UnlockView(gate: self))
            window.center()
            gateWindow = window
        }
        NSApp.activate()
        gateWindow?.makeKeyAndOrderFront(nil)
        requestAutomaticUnlock()
        beginEmbeddedAuthentication()
    }

    @objc private func refreshCovers() {
        if apps.isEmpty {
            coverTimer?.invalidate()
            coverTimer = nil
        } else if coverTimer == nil {
            coverTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self,
                                             selector: #selector(refreshCovers), userInfo: nil, repeats: true)
            coverTimer?.tolerance = 0.05
        }
        var lockedApps: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, let record = apps.first(where: { $0.id == id }),
               !state.isUnlocked(id, processID: app.processIdentifier) {
                lockedApps[app.processIdentifier] = record.name
            }
        }
        windowsCovered = covers.update(lockedApps: lockedApps)
        if !windowsCovered { notice = coverageFailure }
        else if notice == coverageFailure { notice = nil }
        if let target = gateTarget, target.isTerminated { keepLocked(); return }
        if !windowsCovered {
            gateNotice = notice
        } else if gateNotice == coverageFailure {
            gateNotice = nil
        }
        requestAutomaticUnlock()
        beginEmbeddedAuthentication()
    }

    private func requestAutomaticUnlock() {
        guard promptOnActivation, windowsCovered, gateWindow?.isVisible == true, context == nil else { return }
        promptOnActivation = false
        unlockApp()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === gateWindow else { return }
        requestAutomaticUnlock()
        beginEmbeddedAuthentication()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === gateWindow { keepLocked() }
    }

    func unlockApp() {
        guard let target = gateTarget, let record = gateApp else { return }
        promptOnActivation = false
        guard context == nil else { return }
        refreshCovers()
        guard windowsCovered else { gateNotice = notice; return }
        gateNotice = nil
        authenticate(reason: "Unlock \(record.name)") { [weak self] success, message in
            guard let self, self.gateTarget?.processIdentifier == target.processIdentifier else { return }
            self.gateNotice = message
            guard success else { return }
            guard !target.isTerminated else { self.keepLocked(); return }
            self.state.unlock(record.id, processID: target.processIdentifier)
            self.gateTarget = nil
            self.gateApp = nil
            self.gateWindow?.orderOut(nil)
            self.refreshCovers()
            NSApp.yieldActivation(to: target)
            target.activate(options: [])
        }
    }

    func keepLocked() {
        if let target = gateTarget { cancelledPIDs.insert(target.processIdentifier) }
        cancelAuthentication()
        promptOnActivation = false
        gateTarget = nil
        gateApp = nil
        gateWindow?.orderOut(nil)
    }

    func lockAll() {
        keepLocked()
        state.lock()
        cancelledPIDs.removeAll()
        refreshCovers()
    }

    @objc private func systemLocked(_ notification: Notification) { lockAll() }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if let id = app.bundleIdentifier { state.lock(id) }
        if app.processIdentifier == gateTarget?.processIdentifier { keepLocked() }
        cancelledPIDs.remove(app.processIdentifier)
        refreshCovers()
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

    func setLockMode(_ mode: LockMode) {
        guard mode != lockMode else { return }
        authenticate(reason: "Change when TouchGate relocks apps") { [weak self] success, message in
            guard let self else { return }
            self.notice = message
            guard success else { return }
            self.lockMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "lockMode")
            self.state = LockState(mode: mode)
            self.lockAll()
        }
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
                self.covers.clear()
                NSApp.terminate(nil)
            }
        }
    }
}

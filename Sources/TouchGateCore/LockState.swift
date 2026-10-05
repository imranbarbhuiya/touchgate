public enum LockMode: String, CaseIterable {
    case everyActivation
    case oncePerLaunch
}

public struct LockState {
    public let mode: LockMode
    public private(set) var unlockedAppID: String?
    private var unlockedProcesses: [String: Int32] = [:]

    public init(mode: LockMode = .everyActivation) { self.mode = mode }

    public mutating func requiresAuthentication(for appID: String?, processID: Int32 = 0, protectedApps: Set<String>, lockerID: String) -> Bool {
        guard let appID else { unlockedAppID = nil; return false }
        guard appID != lockerID else { return false }
        if appID != unlockedAppID || unlockedProcesses[appID] != processID { unlockedAppID = nil }
        if mode == .oncePerLaunch {
            return protectedApps.contains(appID) && unlockedProcesses[appID] != processID
        }
        return protectedApps.contains(appID) && unlockedAppID != appID
    }

    public func isUnlocked(_ appID: String, processID: Int32) -> Bool {
        mode == .oncePerLaunch ? unlockedProcesses[appID] == processID : unlockedAppID == appID && unlockedProcesses[appID] == processID
    }

    public mutating func unlock(_ appID: String, processID: Int32 = 0) {
        unlockedAppID = appID
        unlockedProcesses[appID] = processID
    }

    public mutating func lock(_ appID: String) {
        unlockedProcesses.removeValue(forKey: appID)
        if unlockedAppID == appID { unlockedAppID = nil }
    }

    public mutating func lock() {
        unlockedAppID = nil
        unlockedProcesses.removeAll()
    }
}

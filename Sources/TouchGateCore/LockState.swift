public struct LockState {
    public private(set) var unlockedAppID: String?

    public init() {}

    public mutating func requiresAuthentication(for appID: String?, protectedApps: Set<String>, lockerID: String) -> Bool {
        guard let appID else { unlockedAppID = nil; return false }
        guard appID != lockerID else { return false }
        if appID != unlockedAppID { unlockedAppID = nil }
        return protectedApps.contains(appID) && unlockedAppID != appID
    }

    public mutating func unlock(_ appID: String) { unlockedAppID = appID }
    public mutating func lock() { unlockedAppID = nil }
}

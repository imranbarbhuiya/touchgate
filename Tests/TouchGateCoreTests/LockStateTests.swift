import XCTest
import TouchGateCore

final class LockStateTests: XCTestCase {
    let protectedApps: Set<String> = ["example.chat", "example.messages"]
    let lockerID = "example.locker"

    func testUnlockOnlyAppliesToCurrentApp() {
        var state = LockState()
        XCTAssertTrue(state.requiresAuthentication(for: "example.chat", protectedApps: protectedApps, lockerID: lockerID))
        state.unlock("example.chat")
        XCTAssertFalse(state.requiresAuthentication(for: "example.chat", protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertTrue(state.requiresAuthentication(for: "example.messages", protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertNil(state.unlockedAppID)
    }

    func testSwitchingAwayRelocksButLockerDoesNot() {
        var state = LockState()
        state.unlock("example.chat")
        XCTAssertFalse(state.requiresAuthentication(for: lockerID, protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertEqual(state.unlockedAppID, "example.chat")
        XCTAssertFalse(state.requiresAuthentication(for: "example.browser", protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertTrue(state.requiresAuthentication(for: "example.chat", protectedApps: protectedApps, lockerID: lockerID))
    }

    func testExplicitLockAndMissingAppIdentity() {
        var state = LockState()
        state.unlock("example.chat")
        state.lock()
        XCTAssertTrue(state.requiresAuthentication(for: "example.chat", protectedApps: protectedApps, lockerID: lockerID))
        state.unlock("example.chat")
        XCTAssertFalse(state.requiresAuthentication(for: nil, protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertNil(state.unlockedAppID)
    }
}

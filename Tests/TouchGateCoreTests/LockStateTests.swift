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
    func testOncePerLaunchKeepsIndependentGrantsAcrossAppSwitches() {
        var state = LockState(mode: .oncePerLaunch)
        state.unlock("example.chat", processID: 101)
        state.unlock("example.messages", processID: 202)
        XCTAssertFalse(state.requiresAuthentication(for: "example.browser", processID: 303, protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertFalse(state.requiresAuthentication(for: "example.chat", processID: 101, protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertFalse(state.requiresAuthentication(for: "example.messages", processID: 202, protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertTrue(state.isUnlocked("example.chat", processID: 101))
    }

    func testNewProcessNeedsAuthenticationEvenWithoutTerminationNotification() {
        for mode in LockMode.allCases {
            var state = LockState(mode: mode)
            state.unlock("example.chat", processID: 101)
            XCTAssertTrue(state.requiresAuthentication(for: "example.chat", processID: 102, protectedApps: protectedApps, lockerID: lockerID))
            XCTAssertFalse(state.isUnlocked("example.chat", processID: 102))
        }
    }

    func testTerminationRevokesOnlyThatAppAndLockAllRevokesEveryGrant() {
        var state = LockState(mode: .oncePerLaunch)
        state.unlock("example.chat", processID: 101)
        state.unlock("example.messages", processID: 202)
        state.lock("example.chat")
        XCTAssertTrue(state.requiresAuthentication(for: "example.chat", processID: 101, protectedApps: protectedApps, lockerID: lockerID))
        XCTAssertFalse(state.requiresAuthentication(for: "example.messages", processID: 202, protectedApps: protectedApps, lockerID: lockerID))
        state.lock()
        XCTAssertTrue(state.requiresAuthentication(for: "example.messages", processID: 202, protectedApps: protectedApps, lockerID: lockerID))
    }
}

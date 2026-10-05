import CoreGraphics
import XCTest
@testable import TouchGateCore

final class WindowCoverageTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testForegroundWindowFullyOccludesProtectedWindow() {
        XCTAssertTrue(WindowCoverage.visibleRegions(of: frame, behind: [frame]).isEmpty)
    }

    func testCentralOccluderLeavesFourDisjointRegions() {
        let occluder = CGRect(x: 20, y: 30, width: 40, height: 50)
        let regions = WindowCoverage.visibleRegions(of: frame, behind: [occluder])
        XCTAssertEqual(regions.count, 4)
        XCTAssertEqual(regions.reduce(0) { $0 + $1.width * $1.height }, 8000)
        for (index, region) in regions.enumerated() {
            XCTAssertTrue(region.intersection(occluder).isEmpty)
            for other in regions.dropFirst(index + 1) {
                XCTAssertTrue(region.intersection(other).isEmpty)
            }
        }
    }

    func testOverlappingOccludersSubtractUnionOnce() {
        let occluders = [CGRect(x: 0, y: 0, width: 60, height: 100),
                         CGRect(x: 40, y: 0, width: 40, height: 100)]
        XCTAssertEqual(WindowCoverage.visibleRegions(of: frame, behind: occluders),
                       [CGRect(x: 80, y: 0, width: 20, height: 100)])
    }

    func testNonOverlappingAndEmptyWindows() {
        XCTAssertEqual(WindowCoverage.visibleRegions(of: frame, behind: [CGRect(x: 200, y: 0, width: 50, height: 50)]), [frame])
        XCTAssertTrue(WindowCoverage.visibleRegions(of: .zero, behind: []).isEmpty)
    }

    func testCoordinatesOnDisplaysAboveAndLeftOfPrimary() {
        XCTAssertEqual(WindowCoverage.appKitFrame(from: CGRect(x: -500, y: -200, width: 300, height: 100), primaryDisplayTop: 900),
                       CGRect(x: -500, y: 1000, width: 300, height: 100))
        XCTAssertEqual(WindowCoverage.appKitFrame(from: CGRect(x: 100, y: 1000, width: 300, height: 100), primaryDisplayTop: 900),
                       CGRect(x: 100, y: -200, width: 300, height: 100))
    }
}

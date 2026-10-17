import XCTest
@testable import ZhuyinEngine

final class CandidateOrientationTests: XCTestCase {
    var testDefaults: UserDefaults!
    var prefs: HaoZhuyinPreferences!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.preferences.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        prefs = HaoZhuyinPreferences(userDefaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultPreferenceValues() {
        // Defaults: spatial tolerance enabled = false, orientation = horizontal
        XCTAssertFalse(prefs.isSpatialToleranceEnabled, "Spatial tolerance should be false by default")
        XCTAssertEqual(prefs.candidateOrientation, .horizontal, "Candidate orientation should be horizontal by default")
    }

    func testOrientationPersistenceAndNotification() {
        var notificationFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: HaoZhuyinPreferences.didChangeNotification,
            object: prefs,
            queue: nil
        ) { _ in
            notificationFired = true
        }

        // Change orientation to vertical
        prefs.candidateOrientation = .vertical
        XCTAssertEqual(prefs.candidateOrientation, .vertical)
        XCTAssertTrue(notificationFired)

        // Verify direct UserDefaults value
        let storedVal = testDefaults.string(forKey: HaoZhuyinPreferences.candidateOrientationKey)
        XCTAssertEqual(storedVal, "vertical")

        NotificationCenter.default.removeObserver(observer)
    }

    func testSpatialTolerancePersistenceAndNotification() {
        var notificationFired = false
        let observer = NotificationCenter.default.addObserver(
            forName: HaoZhuyinPreferences.didChangeNotification,
            object: prefs,
            queue: nil
        ) { _ in
            notificationFired = true
        }

        // Toggle spatial tolerance on
        prefs.isSpatialToleranceEnabled = true
        XCTAssertTrue(prefs.isSpatialToleranceEnabled)
        XCTAssertTrue(notificationFired)

        // Verify direct UserDefaults value
        let storedVal = testDefaults.bool(forKey: HaoZhuyinPreferences.spatialToleranceKey)
        XCTAssertTrue(storedVal)

        NotificationCenter.default.removeObserver(observer)
    }
}

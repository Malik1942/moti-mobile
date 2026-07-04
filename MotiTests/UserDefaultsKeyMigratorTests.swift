import XCTest
@testable import Moti

/// Verifies the one-time legacy-key migration: value/type preservation,
/// idempotency, no-clobber, and no-op on absent keys.
final class UserDefaultsKeyMigratorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Isolated suite so the test never touches the real standard defaults.
        suiteName = "UserDefaultsKeyMigratorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_migratesFlagValueAndRemovesLegacyKey() {
        defaults.set(true, forKey: "useLifelineTimeline")

        UserDefaultsKeyMigrator.run(defaults)

        XCTAssertNil(defaults.object(forKey: "useLifelineTimeline"), "legacy key should be cleared")
        XCTAssertEqual(defaults.bool(forKey: "useTrajectoryTimeline"), true, "value should move to the canonical key")
    }

    func test_preservesCollectionValueTypes() {
        defaults.set(["a", "b"], forKey: "lifelines.pausedStrandIDs")
        defaults.set(["s1": "2026-W20"], forKey: "lifelines.parkedStrandWeek")

        UserDefaultsKeyMigrator.run(defaults)

        XCTAssertEqual(defaults.stringArray(forKey: "strand.pausedIDs"), ["a", "b"])
        XCTAssertEqual(defaults.dictionary(forKey: "strand.parkedWeek") as? [String: String], ["s1": "2026-W20"])
        XCTAssertNil(defaults.object(forKey: "lifelines.pausedStrandIDs"))
        XCTAssertNil(defaults.object(forKey: "lifelines.parkedStrandWeek"))
    }

    func test_idempotent_secondRunIsNoOpAndPreservesValue() {
        defaults.set(true, forKey: "useLifelineTimeline")

        UserDefaultsKeyMigrator.run(defaults)
        UserDefaultsKeyMigrator.run(defaults)   // second run must not disturb the migrated value

        XCTAssertEqual(defaults.bool(forKey: "useTrajectoryTimeline"), true)
        XCTAssertNil(defaults.object(forKey: "useLifelineTimeline"))
    }

    func test_doesNotClobberExistingCanonicalValue() {
        defaults.set(false, forKey: "useLifelineTimeline")   // legacy present…
        defaults.set(true, forKey: "useTrajectoryTimeline")  // …but canonical already set

        UserDefaultsKeyMigrator.run(defaults)

        XCTAssertEqual(defaults.bool(forKey: "useTrajectoryTimeline"), true, "existing canonical value must win")
        XCTAssertNil(defaults.object(forKey: "useLifelineTimeline"), "legacy key still cleared")
    }

    func test_noOpWhenNoLegacyKeysPresent() {
        UserDefaultsKeyMigrator.run(defaults)

        XCTAssertNil(defaults.object(forKey: "useTrajectoryTimeline"))
        XCTAssertNil(defaults.object(forKey: "strand.pausedIDs"))
    }
}

//
// HorizonInstrumentationTests.swift
//
// Horizon Timeline v2 — T13. Local event logging (PRD §10): append, count,
// persist, export, reset.
//

import XCTest
@testable import Moti

final class HorizonInstrumentationTests: XCTestCase {

    private func fresh() -> (HorizonInstrumentation, UserDefaults) {
        let d = UserDefaults(suiteName: "horizon.events.test.\(UUID().uuidString)")!
        return (HorizonInstrumentation(defaults: d), d)
    }

    func test_record_appendsWithDetail_andCounts() {
        let (inst, _) = fresh()
        inst.record(.horizonOpen)
        inst.record(.bucketExpand, detail: "today")
        inst.record(.horizonOpen)
        XCTAssertEqual(inst.events.count, 3)
        XCTAssertEqual(inst.count(.horizonOpen), 2)
        XCTAssertEqual(inst.count(.mapOpen), 0)
        XCTAssertEqual(inst.events.first { $0.kind == .bucketExpand }?.detail, "today")
    }

    func test_persistsAcrossInstances() {
        let (inst, defaults) = fresh()
        inst.record(.mapOpen)
        inst.record(.pastOpen)
        let reopened = HorizonInstrumentation(defaults: defaults)
        XCTAssertEqual(reopened.count(.mapOpen), 1)
        XCTAssertEqual(reopened.count(.pastOpen), 1)
    }

    func test_reset_clearsMemoryAndStorage() {
        let (inst, defaults) = fresh()
        inst.record(.scanSessionLength, detail: "42")
        inst.reset()
        XCTAssertTrue(inst.events.isEmpty)
        XCTAssertTrue(HorizonInstrumentation(defaults: defaults).events.isEmpty)
    }

    func test_exportText_hasKindAndDetail() {
        let (inst, _) = fresh()
        inst.record(.bucketExpand, detail: "later")
        XCTAssertTrue(inst.exportText().contains("bucketExpand later"),
                      "export should include kind and detail")
    }
}

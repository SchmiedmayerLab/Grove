//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import XCTHealthKit
import XCTest


final class BulkExporterTests: GroveHealthKitTests {
    /// All three tests export the same historical sample set and need the same budget for it.
    private static let exportCompletionTimeout: TimeInterval = 180

    @MainActor
    func testBulkExport() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        app.tapWhenTappable("Bulk Exporter")
        app.tapWhenTappable("Request full access")
        app.handleHealthKitAuthorization()

        app.tapWhenTappable("Add Historical Data")
        XCTAssert(app.staticTexts["Adding Historical Samples…"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Adding Historical Samples…"].waitForNonExistence(timeout: 120))
        XCTAssert(app.buttons["Add Historical Data"].waitForExistence(timeout: 20))

        XCTAssertGreaterThan(waitForTestingSamples(in: app), 0)
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), 0)

        app.tapWhenTappable("Start Bulk Export")
        pauseExport(in: app)
        app.tapWhenTappable("Start", message: "export session never settled into .paused")
        XCTAssert(app.staticTexts["State, completed"].waitForExistence(timeout: Self.exportCompletionTimeout))
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), try XCTUnwrap(app.numTestingSamples))
    }


    @MainActor
    func testBulkExportReset() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        app.tapWhenTappable("Bulk Exporter")
        app.tapWhenTappable("Request full access")
        app.handleHealthKitAuthorization()

        app.tapWhenTappable("Add Historical Data")
        XCTAssert(app.staticTexts["Adding Historical Samples…"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Adding Historical Samples…"].waitForNonExistence(timeout: 120))
        XCTAssert(app.buttons["Add Historical Data"].waitForExistence(timeout: 20))

        XCTAssertGreaterThan(waitForTestingSamples(in: app), 0)
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), 0)

        app.tapWhenTappable("Start Bulk Export")
        pauseExport(in: app)
        XCTAssert(app.buttons["Start"].waitUntilTappable(), "export session never settled into .paused")
        let numExportedSamplesFirstSession = try waitForStableExportedSamples(in: app)
        app.terminate()

        try launchAndHandleInitialStuff(app, resetEverything: false, deleteAllHealthData: false)
        app.tapWhenTappable("Bulk Exporter")
        // a wiped restoration file would redo the first session's batches, which only shows up as arithmetic at the end
        XCTAssertGreaterThan(try XCTUnwrap(app.numCompletedBatches()), 0, "the export session lost its restoration info")
        XCTAssertGreaterThan(waitForTestingSamples(in: app), 0)
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), 0)

        app.tapWhenTappable("Start Bulk Export")
        XCTAssert(app.staticTexts["State, completed"].waitForExistence(timeout: Self.exportCompletionTimeout))
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples) + numExportedSamplesFirstSession, try XCTUnwrap(app.numTestingSamples))
    }


    @MainActor
    func testDeleteSessionRestorationInfo() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        app.tapWhenTappable("Bulk Exporter")
        app.tapWhenTappable("Request full access")
        app.handleHealthKitAuthorization()

        app.tapWhenTappable("Add Historical Data")
        XCTAssert(app.staticTexts["Adding Historical Samples…"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["Adding Historical Samples…"].waitForNonExistence(timeout: 120))
        XCTAssert(app.buttons["Add Historical Data"].waitForExistence(timeout: 20))

        XCTAssertGreaterThan(waitForTestingSamples(in: app), 0)
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), 0)

        app.tapWhenTappable("Start Bulk Export")
        pauseExport(in: app)
        XCTAssert(app.buttons["Start"].waitUntilTappable(), "export session never settled into .paused")
        app.terminate()

        try launchAndHandleInitialStuff(app, resetEverything: false, deleteAllHealthData: false)
        app.tapWhenTappable("Bulk Exporter")
        XCTAssertGreaterThan(waitForTestingSamples(in: app), 0)
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), 0)

        app.tapWhenTappable("Reset ExportSession")

        app.tapWhenTappable("Start Bulk Export")
        XCTAssert(app.staticTexts["State, completed"].waitForExistence(timeout: Self.exportCompletionTimeout))
        XCTAssertEqual(try XCTUnwrap(app.numExportedSamples), try XCTUnwrap(app.numTestingSamples))
    }
}


extension BulkExporterTests {
    @MainActor
    private func pauseExport(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let pause = app.buttons["Pause"]
        XCTAssert(pause.waitUntilTappable(), "export session never entered .running", file: file, line: line)
        // pausing only splits up the work if some of it is already done
        XCTAssert(app.waitForExportedSamples(atLeast: 1), "no batch completed before pausing", file: file, line: line)
        pause.tap()
    }

    /// Waits for the query behind `# Expected Samples` to deliver, returning `0` if it never does.
    @MainActor
    private func waitForTestingSamples(in app: XCUIApplication, timeout: Duration = .seconds(30)) -> Int {
        let deadline = ContinuousClock.now + timeout
        repeat {
            if let numSamples = app.numTestingSamples, numSamples > 0 {
                return numSamples
            }
            sleep(for: .seconds(0.25))
        } while ContinuousClock.now < deadline
        return 0
    }

    /// Reads `# Exported Samples` once it stops moving.
    ///
    /// The batch results are drained by a `Task` of their own, so the counter keeps catching up for a while
    /// after the session has reported itself as paused.
    @MainActor
    private func waitForStableExportedSamples(in app: XCUIApplication, timeout: Duration = .seconds(30)) throws -> Int {
        let deadline = ContinuousClock.now + timeout
        var previous: Int?
        var current = try XCTUnwrap(app.numExportedSamples)
        while current != previous, ContinuousClock.now < deadline {
            previous = current
            sleep(for: .seconds(0.5))
            current = try XCTUnwrap(app.numExportedSamples)
        }
        return current
    }
}


extension XCUIApplication {
    var numExportedSamples: Int? {
        let value = self.staticTexts.matching(NSPredicate(format: "label MATCHES '# Exported Samples, .*'")).firstMatch.value
        return (value as? String).flatMap(Int.init)
    }

    var numTestingSamples: Int? {
        let value = self.staticTexts.matching(NSPredicate(format: "label MATCHES '# Expected Samples, .*'")).firstMatch.value
        return (value as? String).flatMap(Int.init)
    }

    /// The number of batches the export session reports as completed, waiting for the session's section to show up.
    func numCompletedBatches(timeout: TimeInterval = 30) -> Int? {
        let row = self.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Status, Completed '")).firstMatch
        guard row.waitForExistence(timeout: timeout),
              let match = row.label.wholeMatch(of: /Status, Completed (?<completed>[0-9]+) of .*/) else {
            return nil
        }
        return Int(match.output.completed)
    }

    /// Waits until `# Exported Samples` has counted at least `count` samples.
    func waitForExportedSamples(atLeast count: Int, timeout: TimeInterval = 60) -> Bool {
        let predicate = NSPredicate { app, _ in
            ((app as? XCUIApplication)?.numExportedSamples ?? 0) >= count
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func tapWhenTappable(
        _ title: String,
        timeout: TimeInterval = 60,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = self.buttons[title]
        XCTAssert(
            button.waitUntilTappable(timeout: timeout),
            message ?? "Button '\(title)' never became tappable",
            file: file,
            line: line
        )
        button.tap()
    }
}


extension XCUIElement {
    /// Waits until the element exists, is enabled, and is hittable.
    ///
    /// An `AsyncButton` renders before it can accept input, and taps that land in between are dropped silently.
    func waitUntilTappable(timeout: TimeInterval = 60) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true AND isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

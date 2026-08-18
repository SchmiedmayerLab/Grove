//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveHealthKit
import XCTest
import XCTestExtensions
import XCTHealthKit


class GroveHealthKitTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    @MainActor
    func launchAndHandleInitialStuff(
        _ app: XCUIApplication,
        resetEverything: Bool,
        askForAuthorization: Bool = true,
        deleteAllHealthData: Bool
    ) throws {
        // The same `XCUIApplication` is relaunched across a test, so a stale flag would reset state the test still needs.
        app.launchArguments.removeAll { $0 == "--resetEverything" }
        if resetEverything {
            app.resetAuthorizationStatus(for: .health)
            app.launchArguments.append("--resetEverything")
        }
        XCTAssert(app.launchAndWait(), "TestApp didn't come up")
        if !app.launchArguments.contains("--collectedSamplesOnly") {
            let alert = app.alerts["“TestApp” Would Like to Send You Notifications"]
            if alert.waitForExistence(timeout: 5) {
                let allow = alert.buttons["Allow"]
                XCTAssert(allow.wait(for: \.isHittable, toEqual: true, timeout: 10))
                allow.tap()
            }
        }
        // the button is disabled once everything is authorized, so this only gates on the first screen being up
        let askForAuthorizationButton = app.buttons["Ask for authorization"]
        XCTAssert(askForAuthorizationButton.waitForExistence(timeout: 30))
        if askForAuthorization, askForAuthorizationButton.isEnabled {
            XCTAssert(askForAuthorizationButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
            askForAuthorizationButton.tap()
            app.handleHealthKitAuthorization()
        }
        if deleteAllHealthData {
            try app.deleteAllHealthData()
        }
    }
    
    @MainActor
    func addSample(_ sampleType: SampleType<HKQuantitySample>, in app: XCUIApplication) {
        app.performMoreMenuAction("Add Sample: \(sampleType.displayTitle)")
    }
    
    
    @MainActor
    func triggerDataCollection(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Trigger data source collection"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Trigger data source collection"].tap()
        XCTAssertTrue(app.buttons["Triggering data source collection"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Trigger data source collection"].waitForExistence(timeout: 10))
    }
}


extension GroveHealthKitTests {
    typealias NumSamplesByType = [SampleType<HKQuantitySample>: Int]
    
    @MainActor
    func assertCollectedSamplesSinceLaunch(
        in app: XCUIApplication,
        _ expectedNumSamplesBySampleType: NumSamplesByType,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = Dictionary(uniqueKeysWithValues: expectedNumSamplesBySampleType.map { ($0.hkSampleType.identifier, $1) })
        @MainActor
        func imp(try: Int) {
            // swiftlint:disable:next empty_count
            let staticTexts = app.staticTexts.count > 0
                ? app.staticTexts.allElementsBoundByIndex.compactMap { $0.exists ? $0.label : nil }
                : []
            guard `try` > 0 else {
                XCTFail("Unable to check (staticTexts: \(staticTexts))", file: file, line: line)
                return
            }
            guard staticTexts.count > 0 else { // swiftlint:disable:this empty_count
                sleep(for: .seconds(2))
                imp(try: `try` - 1)
                return
            }
            let actual: [String: Int] = Dictionary(uniqueKeysWithValues: staticTexts.compactMap { text in
                let pattern = /(?<type>HK[a-zA-Z]+), (?<count>[0-9]+)/
                guard let match = text.wholeMatch(of: pattern),
                      let count = Int(match.output.count) else {
                    return nil
                }
                return (String(match.output.type), count)
            })
            if expected != actual, `try` > 1 {
                // try again
                sleep(for: .seconds(2))
                imp(try: `try` - 1)
                return
            } else {
                XCTAssertEqual(actual, expected, file: file, line: line)
            }
        }
        imp(try: 5)
    }
}


extension XCUIApplication {
    convenience init(launchArguments: [String]) {
        self.init()
        self.launchArguments.append(contentsOf: launchArguments)
    }
    
    func assertTableRow(_ title: String, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label = %@", "\(title), \(value)")
        XCTAssert(
            self.staticTexts.matching(predicate).element.waitForExistence(timeout: 10),
            "Unable to find element '\(predicate)'",
            file: file,
            line: line
        )
    }
    
    @MainActor
    func deleteAllHealthData() throws {
        #if !targetEnvironment(simulator)
        let msg = "Refusing to delete HealthData on a non-simulator device"
        XCTFail(msg)
        throw XCTSkip(msg)
        #else
        self.performMoreMenuAction("Delete Test Data from HealthKit")
        #endif
    }
    
    @MainActor
    func performMoreMenuAction(_ pathFst: String, _ pathRest: String...) {
        let menuButton = self.navigationBars.buttons["actions"]
        XCTAssert(menuButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
        guard let completedActions = menuButton.completedActions else {
            XCTFail("The actions menu doesn't report the number of actions it has completed")
            return
        }
        menuButton.tap()
        for title in [pathFst] + pathRest {
            let button = self.buttons[title]
            XCTAssert(button.waitUntilTappable(timeout: 30), "Menu action '\(title)' never became tappable")
            button.tap()
        }
        XCTAssert(
            menuButton.waitForCompletedActions(above: completedActions, timeout: 30),
            "Menu action '\(pathFst)' never completed"
        )
    }
}


extension XCUIElement {
    /// Waits until the element exists, is enabled, and is hittable.
    ///
    /// SwiftUI controls can enter the accessibility tree before their presentation finishes and they accept input.
    func waitUntilTappable(timeout: TimeInterval = 60) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true AND isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The number of actions the `ActionsMenu` this element represents has run to completion.
    var completedActions: Int? {
        (self.value as? String).flatMap(Int.init)
    }

    /// Waits until the `ActionsMenu` this element represents reports more than `count` completed actions.
    ///
    /// Selecting a menu entry only kicks off its action; everything it writes to HealthKit lands afterwards.
    func waitForCompletedActions(above count: Int, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { element, _ in
            ((element as? XCUIElement)?.completedActions ?? 0) > count
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}


func sleep(for duration: Duration) {
    usleep(UInt32(duration.timeInterval * 1000000))
}

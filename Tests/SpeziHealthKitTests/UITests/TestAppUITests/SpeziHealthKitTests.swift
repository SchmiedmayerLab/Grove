//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziHealthKit
import XCTest
import XCTestExtensions
import XCTHealthKit


class SpeziHealthKitTests: XCTestCase {
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
        if resetEverything {
            app.resetAuthorizationStatus(for: .health)
            app.launchArguments.append("--resetEverything")
        }
        app.launch()
        XCTAssert(app.wait(for: .runningForeground, timeout: 10))
        if !app.launchArguments.contains("--collectedSamplesOnly") {
            if app.alerts["“TestApp” Would Like to Send You Notifications"].waitForExistence(timeout: 5) {
                app.alerts["“TestApp” Would Like to Send You Notifications"].buttons["Allow"].tap()
            }
        }
        XCTAssert(app.buttons["Ask for authorization"].waitForExistence(timeout: 10))
        if askForAuthorization, app.buttons["Ask for authorization"].isEnabled {
            app.buttons["Ask for authorization"].tap()
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
        XCTAssertTrue(app.buttons["Trigger data source collection"].waitForExistence(timeout: 10))
        app.buttons["Trigger data source collection"].tap()
        XCTAssertTrue(app.buttons["Triggering data source collection"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Trigger data source collection"].waitForExistence(timeout: 10))
    }
}


extension SpeziHealthKitTests {
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
        XCTAssert(menuButton.waitForExistence(timeout: 10))
        menuButton.tap()
        for title in [pathFst] + pathRest {
            let button = self.buttons[title]
            XCTAssert(button.waitForExistence(timeout: 10))
            button.tap()
            sleep(for: .seconds(0.5)) // i sleep
        }
    }
}


func sleep(for duration: Duration) {
    usleep(UInt32(duration.timeInterval * 1000000))
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HealthKit
import GroveHealthKit
import XCTest
import XCTestExtensions
import XCTHealthKit


final class HealthKitQueryTests: GroveHealthKitTests {
    @MainActor
    func testHealthKitQuery() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        
        for _ in 0..<7 {
            addSample(.stepCount, in: app)
        }
        
        XCTAssert(app.buttons["Samples Query"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Samples Query"].tap()
        XCTAssert(app.staticTexts["Steps, 152"].waitForExistence(timeout: 3))
    }
    
    
    @MainActor
    func testHealthKitStatisticsQuery() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        
        for _ in 0..<7 {
            addSample(.stepCount, in: app)
        }
        
        XCTAssert(app.buttons["Statistics Query"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Statistics Query"].tap()
        
        let now = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let fmt = { String(format: "%02d", $0) }
        let todayPred = NSPredicate(
            format: "label MATCHES %@",
            "Steps on \(fmt(try XCTUnwrap(now.year)))-\(fmt(try XCTUnwrap(now.month)))-\(fmt(try XCTUnwrap(now.day))).*"
        )
        XCTAssert(app.staticTexts.element(matching: todayPred).waitForExistence(timeout: 10))
    }
    
    @MainActor
    func testHealthKitCollectStatisticsQuery() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        
        for _ in 0..<3 {
            addSample(.stepCount, in: app)
        }
        addSample(.heartRate, in: app)
        
        XCTAssert(app.buttons["Collect Statistics Query"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Collect Statistics Query"].tap()
        
        XCTAssert(app.buttons["Trigger Statistics Queries"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Trigger Statistics Queries"].tap()

        let now = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let fmt = { String(format: "%02d", $0) }
        let todayPred = NSPredicate(
            format: "label MATCHES %@",
            "Steps on \(fmt(try XCTUnwrap(now.year)))-\(fmt(try XCTUnwrap(now.month)))-\(fmt(try XCTUnwrap(now.day))).*"
        )
        // the rows below only get rendered once the queries the tap kicked off have delivered
        XCTAssert(app.staticTexts.element(matching: todayPred).waitForExistence(timeout: 10))

        func assertHRRow(_ identifier: String) {
            let value = app.staticTexts["hr-value-\(identifier)"]
            XCTAssert(value.waitForExistence(timeout: 10))
            XCTAssertEqual(value.label, "87 count/min")
        }
        
        assertHRRow("average")
        assertHRRow("minimum")
        assertHRRow("maximum")
    }
    
    
    @MainActor
    func testCharacteristicsQuery() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        
        let dateOfBirthComponents = DateComponents(
            calendar: .init(identifier: .gregorian),
            timeZone: .current,
            era: 1,
            year: 2022,
            month: 10,
            day: 11
        )
        let dateOfBirth = try XCTUnwrap(Calendar.current.date(from: dateOfBirthComponents))
        
        try launchHealthAppAndEnterCharacteristics(.init(
            bloodType: .oPositive,
            dateOfBirth: dateOfBirthComponents,
            biologicalSex: .female,
            skinType: .I,
            wheelchairUse: .no
        ))
        
        app.activate()
        XCTAssert(app.buttons["Characteristics Query"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Characteristics Query"].tap()
        
        app.assertTableRow("Move Mode", "1")
        app.assertTableRow("Blood Type", "O+")
        app.assertTableRow("Date of Birth", dateOfBirth.formatted(.iso8601))
        app.assertTableRow("Date of Birth is Midnight", "true")
        app.assertTableRow("Date of Birth Components", dateOfBirthComponents.description)
        app.assertTableRow("Biological Sex", "1")
        app.assertTableRow("Skin Type", "1")
        app.assertTableRow("Wheelchair Use", "1")
    }
    
    
    @MainActor
    func testScoredAssessments() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        
        XCTAssert(app.buttons["Scored Assessments"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Scored Assessments"].tap()

        XCTAssert(app.staticTexts["No GAD-7 Assessments"].waitForExistence(timeout: 2))
        XCTAssert(app.staticTexts["No PHQ-9 Assessments"].waitForExistence(timeout: 2))

        func addScore(_ name: String) {
            // the menu button only becomes hittable again once the previous menu has been dismissed
            let menuButton = app.navigationBars.buttons["Add"]
            XCTAssert(menuButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
            menuButton.tap()
            let addSampleButton = app.buttons["Add Sample: \(name)"]
            XCTAssert(addSampleButton.wait(for: \.isHittable, toEqual: true, timeout: 10))
            addSampleButton.tap()
        }
        
        addScore("GAD-7")
        XCTAssert(app.staticTexts["No GAD-7 Assessments"].waitForNonExistence(timeout: 2))
        app.assertTableRow("Date", "2025-04-25")
        app.assertTableRow("Risk", "2")
        app.assertTableRow("Answers", "2;3;0;1;1;0;2")
        
        addScore("PHQ-9")
        XCTAssert(app.staticTexts["No PHQ-9 Assessments"].waitForNonExistence(timeout: 2))
        app.assertTableRow("Date", "2025-04-27")
        app.assertTableRow("Risk", "3")
        app.assertTableRow("Answers", "2;3;0;1;1;0;2;3;1")
    }
    
    
    @MainActor
    func testSleepSession() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        
        XCTAssert(app.buttons["Sleep Sessions"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Sleep Sessions"].tap()

        // branch on the observed outcome of the fetch rather than on the assumption that it has finished by now
        let fetched = app.staticTexts.matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "No Sleep Data", "Tracked Time")
        ).firstMatch
        XCTAssert(fetched.waitForExistence(timeout: 30))

        if app.staticTexts["No Sleep Data"].exists {
            let addSamples = app.navigationBars.buttons["Add Samples"]
            XCTAssert(addSamples.wait(for: \.isHittable, toEqual: true, timeout: 10))
            addSamples.tap()
        }
        XCTAssert(app.staticTexts["Tracked Time"].waitForExistence(timeout: 30))
        
        XCTAssert(app.staticTexts["Tracked Time, 7:35:30"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Time Awake, 0:19:00"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Time Asleep, 7:16:30"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["#Samples, 31"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Time: Core Sleep, 4:42:30"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Time: Deep Sleep, 1:02:00"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Time: REM Sleep, 1:32:00"].waitForExistence(timeout: 1))
    }
    
    
    @MainActor
    func testSleepSession2() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        XCTAssert(app.buttons["Sleep Tests"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Sleep Tests"].tap()
        XCTAssert(app.staticTexts["Success"].waitForExistence(timeout: 5))
    }
    
    
    @MainActor
    func testDeferredAuthorization() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly", "--disable-blood-type-auth-request"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)
        addSample(.distanceCycling, in: app)
        try launchHealthAppAndEnterCharacteristics(.init(
            bloodType: .oPositive
        ))
        
//        app.delete(app: "TestApp")
        try launchAndHandleInitialStuff(app, resetEverything: true, askForAuthorization: false, deleteAllHealthData: false)
        
        XCTAssert(app.buttons["Deferred Authorization"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Deferred Authorization"].tap()

        app.assertTableRow("Blood Type", "n/a")
        app.assertTableRow("#cyclingSamples", "0")
        app.assertTableRow("#km cycled", "0")

        XCTAssert(app.buttons["Request Blood Type"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Request Blood Type"].tap()
        app.handleHealthKitAuthorization()
        app.assertTableRow("Blood Type", "O+")

        XCTAssert(app.buttons["Request Cycling Distance"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Request Cycling Distance"].tap()
        app.handleHealthKitAuthorization()
        app.assertTableRow("#cyclingSamples", "1")
        app.assertTableRow("#km cycled", "52")
    }
    
    
    // The samples this adds via the Health app belong to another source and therefore survive every
    // `deleteAllHealthData`; the counts below are asserted relative to what the store already holds.
    @MainActor
    func testSourceFiltering() throws {
        let app = XCUIApplication(launchArguments: ["--collectedSamplesOnly"])
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: true)

        XCTAssert(app.buttons["Source Filtering"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Source Filtering"].tap()
        let baselineAll = app.sourceFilteringCount("All")
        let baselineHealthApp = app.sourceFilteringCount("Health.app")
        app.tapBackButton("HealthKit")
        app.terminate()

        let healthApp = XCUIApplication.healthApp
        XCTAssert(healthApp.launchAndWait(), "The Health app didn't come up")
        if healthApp.staticTexts["Health Details"].waitForExistence(timeout: 2) {
            for label in ["close", "Close"] {
                let button = healthApp.navigationBars.buttons[label]
                if button.exists {
                    button.tap()
                    break
                }
            }
        }
        
        try launchAndAddSamples(healthApp: .healthApp, [
            .steps()
        ])
        
        try launchAndHandleInitialStuff(app, resetEverything: true, deleteAllHealthData: false)

        XCTAssert(app.buttons["Source Filtering"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Source Filtering"].tap()
        XCTAssert(app.staticTexts["# All Samples, \(baselineAll + 1)"].waitForExistence(timeout: 30))
        XCTAssert(app.staticTexts["# Health.app Samples, \(baselineHealthApp + 1)"].waitForExistence(timeout: 30))
        // only meaningful once the counts above have arrived: all three queries start out empty, and 0 == 0 + 0
        XCTAssert(app.staticTexts["Sample Counts Add Up, true"].exists)
        XCTAssertEqual(app.sourceFilteringCount("Our", timeout: 1), 0)

        app.tapBackButton("HealthKit")
        addSample(.stepCount, in: app)

        XCTAssert(app.buttons["Source Filtering"].wait(for: \.isHittable, toEqual: true, timeout: 10))
        app.buttons["Source Filtering"].tap()
        XCTAssert(app.staticTexts["# All Samples, \(baselineAll + 2)"].waitForExistence(timeout: 30))
        XCTAssert(app.staticTexts["# Our Samples, 1"].waitForExistence(timeout: 30))
        XCTAssert(app.staticTexts["# Health.app Samples, \(baselineHealthApp + 1)"].waitForExistence(timeout: 30))
        XCTAssert(app.staticTexts["Sample Counts Add Up, true"].exists)
    }
}


extension XCUIApplication {
    /// Taps the navigation bar's back button, once the push animation has settled.
    @MainActor
    func tapBackButton(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = navigationBars.buttons[title]
        XCTAssert(
            button.wait(for: \.isHittable, toEqual: true, timeout: 10),
            "Back button '\(title)' never became hittable",
            file: file,
            line: line
        )
        button.tap()
    }

    /// The sample count shown in the given section of the Source Filtering screen.
    ///
    /// `SourceFilteredQueryView` omits a section entirely when its query is empty, so a missing row reads as `0`.
    func sourceFilteringCount(_ title: String, timeout: TimeInterval = 5) -> Int {
        let row = staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "# \(title) Samples, ")).firstMatch
        guard row.waitForExistence(timeout: timeout),
              let count = row.label.split(separator: ", ").last.flatMap({ Int($0.filter(\.isNumber)) }) else {
            return 0
        }
        return count
    }
}

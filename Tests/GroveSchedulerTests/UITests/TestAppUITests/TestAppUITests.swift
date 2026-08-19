//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions
import XCTGroveNotifications

/// Scheduler notification identifiers are derived from the host app's bundle identifier, so they are
/// no longer a fixed vendor string. Kept in one place: the TestApp's bundle id decides the value.
private let schedulerNotificationPrefix = "org.grovealliance.grovescheduler.testapp.scheduler.notification"


class TestAppUITests: XCTestCase { // swiftlint:disable:this type_body_length
    private var uses12HourClock: Bool {
        switch Locale.current.hourCycle {
        case .zeroToEleven, .oneToTwelve:
            true
        case .zeroToTwentyThree, .oneToTwentyFour:
            false
        @unknown default:
            true // just assume it's running in the US
        }
    }
    
    override func setUp() {
        continueAfterFailure = false
    }


    @MainActor
    func testBasicEventInteraction() {
        let app = XCUIApplication()
        // The Scheduler stores outcomes on disk, so a surviving container would leave the questionnaire
        // already completed and the "Complete Questionnaire" button gone.
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssert(app.staticTexts["Schedule"].waitForExistence(timeout: 10.0))
        XCTAssert(app.staticTexts["Today"].exists)

        app.swipeUp()

        XCTAssert(app.staticTexts["Social Support Questionnaire"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Questionnaire"].exists)
        if uses12HourClock {
            XCTAssert(app.staticTexts["4:00 PM"].exists)
        } else {
            XCTAssert(app.staticTexts["16:00"].exists)
        }

        let moreInformation = app.buttons.matching(identifier: "More Information").element(boundBy: 1)
        XCTAssert(moreInformation.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        moreInformation.tap()

        XCTAssertTrue(app.navigationBars.staticTexts["More Information"].waitForExistence(timeout: 4.0))
        XCTAssertTrue(app.staticTexts["Instructions"].exists)
        XCTAssertTrue(app.staticTexts["About"].exists)

        let close = app.navigationBars.buttons["Close"]
        XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        close.tap()

        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 2.0))

        let completeQuestionnaire = app.buttons["Complete Questionnaire"]
        XCTAssert(completeQuestionnaire.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        completeQuestionnaire.tap()

        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 2.0))
    }

    
    @MainActor
    func testNotificationScheduling() throws { // swiftlint:disable:this function_body_length
        let leadTime: TimeInterval = 60
        let app = XCUIApplication()
        app.launchArguments += ["-notificationLeadTime", "\(Int(leadTime))"]
        app.delete(app: "TestApp")
        let launchDate = Date.now
        XCTAssert(app.launchAndWait())

        func checkButtonExists(_ name: String, timeout: TimeInterval = 2, line: UInt = #line) {
            XCTAssert(app.buttons[name].waitForExistence(timeout: timeout), line: line)
        }

        checkButtonExists("Complete Measurement", timeout: 10)
        checkButtonExists("Complete Questionnaire")
        XCTAssert(app.scrollToAndTapButton("Complete Enter Lab Results"))

        app.goToTab(.notifications)

        XCTAssert(app.staticTexts["Pending Notifications"].waitForExistence(timeout: 2.0))

        let requestAuthorization = app.navigationBars.buttons["Request Notification Authorization"]
        XCTAssert(requestAuthorization.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        XCTAssert(
            app.staticTexts["Weight Measurement"].waitForExistence(timeout: 5.0),
            "It seems that provisional notification authorization didn't work."
        )

        requestAuthorization.tap()

        app.confirmNotificationAuthorization(requireAlertToAppear: true)

        // The pending notifications list reads the requests once, when it appears; the scheduler registers
        // them one by one after the authorization is granted, so re-read until they are all in.
        let medications = app.staticTexts.matching(identifier: "Medication")
        let refresh = app.navigationBars.buttons["Refresh"]
        let schedulingDeadline = Date.now.addingTimeInterval(30)
        while !medications.element(boundBy: 3).waitForExistence(timeout: 1), Date.now < schedulingDeadline {
            XCTAssert(refresh.wait(for: \.isHittable, toEqual: true, timeout: 2))
            refresh.tap()
        }
        XCTAssert(medications.element(boundBy: 3).exists, "events were never scheduled")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = springboard.otherElements["Notification"].descendants(matching: .any)["NotificationShortLookView"]
        // The banner auto-dismisses after a few seconds, so the wait has to still be running when it fires.
        let remaining = max(leadTime - Date.now.timeIntervalSince(launchDate), 0)
        XCTAssert(
            notification.waitForExistence(timeout: remaining + 20),
            """
            Weight Measurement banner did not arrive within \(remaining + 20)s \
            (lead time \(leadTime)s, \(Date.now.timeIntervalSince(launchDate))s elapsed since launch)
            """
        )
        XCTAssert(notification.staticTexts["Weight Measurement"].exists)
        XCTAssert(notification.staticTexts["Take a weight measurement every day."].exists)
        XCTAssert(notification.wait(for: \.isHittable, toEqual: true, timeout: 5.0))
        notification.tap()

        // Tapping the banner brings the app back to the foreground, which is as slow as a launch.
        let weightMeasurement = app.staticTexts["Weight Measurement"]
        XCTAssert(weightMeasurement.wait(for: \.isHittable, toEqual: true, timeout: 10.0))
        weightMeasurement.tap()

        XCTAssert(app.navigationBars.staticTexts["Weight Measurement"].waitForExistence(timeout: 2.0))
        app.assertNotificationDetails(
            identifier: "\(schedulerNotificationPrefix).task.test-measurement",
            title: "Weight Measurement",
            body: "Take a weight measurement every day.",
            category: "\(schedulerNotificationPrefix).category.measurement",
            thread: "\(schedulerNotificationPrefix)",
            sound: true,
            interruption: .timeSensitive,
            type: "Calendar",
            nextTriggerPrefix: "in ",
            nextTriggerExistenceTimeout: 60
        )

        let backToPendingNotifications = app.navigationBars.buttons["Pending Notifications"]
        XCTAssert(backToPendingNotifications.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        backToPendingNotifications.tap()

        let medication = app.staticTexts["Medication"].firstMatch
        XCTAssert(medication.wait(for: \.isHittable, toEqual: true, timeout: 2.0))
        medication.tap()

        XCTAssert(app.navigationBars.staticTexts["Medication"].waitForExistence(timeout: 2.0))
        app.assertNotificationDetails(
            title: "Medication",
            body: "Take your medication",
            category: "\(schedulerNotificationPrefix).category.medication",
            thread: "\(schedulerNotificationPrefix)",
            sound: true,
            interruption: .timeSensitive,
            type: "Interval",
            nextTriggerPrefix: "in ",
            nextTriggerExistenceTimeout: 60
        )
    }
    
    
    @MainActor
    func testNotificationSchedulingDontNotifyForAlreadyCompletedEvents() throws { // swiftlint:disable:this function_body_length
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssert(app.buttons["Complete Enter Lab Results"].waitForExistence(timeout: 10))

        app.goToTab(.notifications)

        XCTAssert(app.staticTexts["Pending Notifications"].waitForExistence(timeout: 2.0))

        XCTAssert(app.navigationBars.buttons["Request Notification Authorization"].waitForExistence(timeout: 2.0))
        let labResultsNotification = app.staticTexts["Enter Lab Results"]
        XCTAssert(
            labResultsNotification.wait(for: \.isHittable, toEqual: true, timeout: 5.0),
            "It seems that provisional notification authorization didn't work."
        )

        labResultsNotification.tap()

        XCTAssert(app.navigationBars.staticTexts["Enter Lab Results"].waitForExistence(timeout: 2.0))
        app.assertNotificationDetails(
            identifier: "\(schedulerNotificationPrefix).task.enter-lab-results",
            title: "Enter Lab Results",
            body: "You should enter Lab Results into the app at least once every 7 days!",
            category: "\(schedulerNotificationPrefix).category.lab-results",
            thread: "\(schedulerNotificationPrefix)",
            sound: true,
            interruption: .timeSensitive,
            type: "Calendar",
            nextTriggerPrefix: "in ",
            nextTriggerExistenceTimeout: 60
        )
        
        // Complete the task for today
        app.goToTab(.schedule)
        let complete = app.buttons["Complete Enter Lab Results"]
        XCTAssert(app.scrollToAndTapButton("Complete Enter Lab Results"))
        XCTAssert(complete.waitForNonExistence(timeout: 5))
        app.goToTab(.notifications)

        // The tile flips on the outcome save; rewriting the notification is a separate pass, so re-read the
        // list until the event-level request is the one we open.
        let refresh = app.navigationBars.buttons["Refresh"]
        if refresh.wait(for: \.isHittable, toEqual: true, timeout: 2) {
            refresh.tap()
        }
        let eventNotification = app.staticTexts["Enter Lab Results"].firstMatch
        XCTAssert(eventNotification.wait(for: \.isHittable, toEqual: true, timeout: 5))
        eventNotification.tap()

        XCTAssert(app.navigationBars.staticTexts["Enter Lab Results"].waitForExistence(timeout: 2.0))
        let eventIdentifier = NSPredicate(
            format: "label BEGINSWITH %@",
            "Identifier, \(schedulerNotificationPrefix).event.enter-lab-results."
        )
        XCTAssert(app.staticTexts.matching(eventIdentifier).firstMatch.waitForExistence(timeout: 2))
        app.assertNotificationDetails(
            // we can't specify the identifier here, since this is now an event-level-scheduled notification, which includes the event's timestamp.
            // we instead assert the identifier above
            identifier: nil,
            title: "Enter Lab Results",
            body: "You should enter Lab Results into the app at least once every 7 days!",
            category: "\(schedulerNotificationPrefix).category.lab-results",
            thread: "\(schedulerNotificationPrefix)",
            sound: true,
            interruption: .timeSensitive,
            type: "Interval",
            nextTriggerPrefix: "in ",
            nextTriggerExistenceTimeout: 60
        )
    }
    
    
    @MainActor
    func testShadowedOutcomesHandlingWhenReRegisteringSameTask() throws {
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))
        
        let menuButton = app.buttons["Extra Tests"]
        XCTAssert(menuButton.waitForExistence(timeout: 10))
        menuButton.tryToTapReallySoftlyMaybeThisWillMakeItWork()
        let testCaseButton = app.buttons["Shadowed Outcomes"]
        XCTAssert(testCaseButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
        testCaseButton.tap()
        
        XCTAssertTrue(app.staticTexts["Passed"].waitForExistence(timeout: 2))
    }
    
    
    @MainActor
    func testObserveOutcomes() throws {
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")

        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))
        
        let menuButton = app.buttons["Extra Tests"]
        XCTAssert(menuButton.waitForExistence(timeout: 10))
        menuButton.tryToTapReallySoftlyMaybeThisWillMakeItWork()
        let testCaseButton = app.buttons["Observe New Outcomes"]
        XCTAssert(testCaseButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
        testCaseButton.tap()

        XCTAssert(app.staticTexts["did trigger, false"].waitForExistence(timeout: 2))
        let completeButton = app.otherElements["ObserveNewOutcomesView"].buttons["Complete"].firstMatch
        XCTAssert(completeButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
        completeButton.tap()
        XCTAssert(app.staticTexts["did trigger, false"].waitForNonExistence(timeout: 2))
        XCTAssert(app.staticTexts["did trigger, true"].waitForExistence(timeout: 2))
        XCTAssert(completeButton.waitForNonExistence(timeout: 2))
    }
    
    
    @MainActor
    func testExplicitNotificationTime() throws {
        // What we test for here is that, when we define a Task with an explicit notificationTime,
        // the start date of the task's occurrences and the time for which the notifications are scheduled,
        // are both correct (and, importantly, different from each other!).
        // In this case, we have a task that is scheduled for midnight, but doesn't want its notification until 00:05.
        // (Note that the reason why these specific times are chosen is to minimise the likelihood the tests accidentally fail;
        // if the test runs while the next occurrence is > 24 hours away the scheduler needs to fall back to a TimeInterval-based
        // trigger, which we can't (easily) decompose into date components.)
        let app = XCUIApplication()
        app.deleteAndLaunch(withSpringboardAppName: "TestApp")
        XCTAssert(app.wait(for: .runningForeground, timeout: 2.0))
        
        XCTAssert(app.collectionViews.staticTexts["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.collectionViews.staticTexts["Timed Walking Test"].exists)

        // Part 1: verify the Schedule tab
        let more = app.navigationBars.buttons["More"]
        XCTAssert(more.wait(for: \.isHittable, toEqual: true, timeout: 2))
        more.tap()
        let dateMenu = app.buttons["Date"]
        XCTAssert(dateMenu.wait(for: \.isHittable, toEqual: true, timeout: 2))
        dateMenu.tap()
        let tomorrow = app.buttons["Tomorrow"]
        XCTAssert(tomorrow.wait(for: \.isHittable, toEqual: true, timeout: 2))
        tomorrow.tap()
        // Picking another day re-queries the schedule, so the new rows only arrive after a round trip.
        XCTAssert(app.collectionViews.staticTexts["Tomorrow"].waitForExistence(timeout: 5))
        XCTAssert(app.collectionViews.staticTexts["Timed Walking Test"].waitForExistence(timeout: 5))
        XCTAssert(app.collectionViews.staticTexts.matching(
            NSPredicate(format: "label MATCHES 'Timed Walking Test, Active Task, In .*, \(uses12HourClock ? "12:00 AM" : "00:00")'")
        ).element.exists)
        
        // Part 2: verify the actual notification scheduling
        app.goToTab(.notifications)
        XCTAssert(app.staticTexts["Pending Notifications"].waitForExistence(timeout: 1))
        let timedWalkingTest = app.staticTexts["Timed Walking Test"].firstMatch
        XCTAssert(timedWalkingTest.wait(for: \.isHittable, toEqual: true, timeout: 5))
        timedWalkingTest.tap()
        XCTAssert(app.navigationBars.staticTexts["Timed Walking Test"].waitForExistence(timeout: 2.0))
        app.assertNotificationDetails(
            identifier: "\(schedulerNotificationPrefix).task.timed-walking-test",
            title: "Timed Walking Test",
            body: "Walk for 6 minutes!",
            category: "\(schedulerNotificationPrefix).category.timed-walking-test",
            thread: "\(schedulerNotificationPrefix)",
            sound: true,
            interruption: .timeSensitive,
            type: "Calendar",
            nextTrigger: nil
        )
        XCTAssert(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES 'Date, calendar: .*hour: 0 minute: 5 second: 0.*'")
        ).element.exists, "DateComponents don't match expected time values.")
    }
}


extension XCUIApplication {
    enum Tab: String {
        case schedule = "Schedule"
        case notifications = "Notifications"
    }
    
    func goToTab(_ tab: Tab, line: UInt = #line) {
        let tab = self.tabBars.buttons[tab.rawValue]
        XCTAssert(tab.wait(for: \.isHittable, toEqual: true, timeout: 2.0), line: line)
        tab.tap()
        tab.tap()
    }

    @MainActor
    func scrollToAndTapButton(
        _ label: String,
        maximumSwipes: Int = 4,
        timeout: TimeInterval = 5
    ) -> Bool {
        let button = buttons[label]
        var swipes = 0
        while !button.isHittable && swipes < maximumSwipes {
            swipeUp()
            swipes += 1
        }
        guard button.wait(for: \.isHittable, toEqual: true, timeout: timeout) else {
            return false
        }
        button.tap()
        return true
    }
}

extension XCUIElement {
    // This is required to work around an apparent XCTest bug when trying to tap e.g. the Health App's Profile button.
    // See also: https://stackoverflow.com/a/33534187
    func tryToTapReallySoftlyMaybeThisWillMakeItWork() {
        if isHittable {
            tap()
        } else {
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}

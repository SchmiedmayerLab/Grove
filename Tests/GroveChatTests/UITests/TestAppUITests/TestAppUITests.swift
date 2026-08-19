//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


@MainActor
class TestAppUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--testMode"]
        XCTAssert(app.launchAndWait(for: app.textFields["Message Input Textfield"]), "The chat did not come up after launch.")
    }


    func testChat() throws {
        let app = XCUIApplication()

        XCTAssert(app.staticTexts["GroveChat"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Assistant Message!"].waitForExistence(timeout: 1))

        try app.textFields["Message Input Textfield"].enter(value: "User Message!", options: [.disableKeyboardDismiss])
        XCTAssert(app.buttons["Send Message"].wait(for: \.isHittable, toEqual: true, timeout: 2))
        app.buttons["Send Message"].tap()
        XCTAssert(app.otherElements["Typing Indicator"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["User Message!"].waitForExistence(timeout: 5))
        XCTAssert(app.otherElements["Typing Indicator"].waitForNonExistence(timeout: 20))
        XCTAssert(app.staticTexts["Assistant Message Response!"].waitForExistence(timeout: 5))
    }
    
    
    func testChatExport() throws {  // swiftlint:disable:this function_body_length cyclomatic_complexity
        // Skip chat export test on visionOS and macOS
        #if os(visionOS)
        throw XCTSkip("VisionOS is unstable and are skipped at the moment")
        #elseif os(macOS)
        throw XCTSkip("macOS export to a file is not possible (regular sharesheet is)")
        #endif

        let app = XCUIApplication()
        let filesApp = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let maxRetries = 10
        
        let locationPredicate = NSPredicate(format: "label BEGINSWITH[c] %@", "On My")

        // Saving to Files is very flakey on the runners and needs multiple attempts to succeed, so every
        // step in here recovers via `continue` instead of failing the test outright.
        for _ in 0...maxRetries {
            app.launchArguments = ["--testMode"]
            guard app.launchAndWait(for: app.textFields["Message Input Textfield"], timeout: 15) else {
                continue
            }

            // Entering dummy chat value
            try app.textFields["Message Input Textfield"].enter(value: "User Message!", options: [.disableKeyboardDismiss])
            guard app.buttons["Send Message"].wait(for: \.isHittable, toEqual: true, timeout: 5) else {
                continue
            }
            app.buttons["Send Message"].tap()
            guard app.staticTexts["Assistant Message Response!"].waitForExistence(timeout: 10) else {
                continue
            }

            // Export chat via share sheet button
            guard app.buttons["Export the Chat"].wait(for: \.isHittable, toEqual: true, timeout: 5) else {
                continue
            }
            app.buttons["Export the Chat"].tap()

            // Store exported chat in Files
            #if os(visionOS)
            // On visionOS the "Save to files" button has no label
            let saveToFiles = app.cells["XCElementSnapshotPrivilegedValuePlaceholder"]
            #else
            let saveToFiles = app.staticTexts["Save to Files"]
            #endif
            // the share sheet resolves the element before it has finished animating into position;
            // tapping on the moving frame misses.
            guard saveToFiles.waitForExistence(timeout: 15),
                  saveToFiles.wait(for: \.isHittable, toEqual: true, timeout: 5) else {
                continue
            }
            saveToFiles.tap()

            // the document picker shows "Save" from its first render, before any location is chosen
            let save = app.buttons["Save"]
            guard save.waitForExistence(timeout: 15) else {
                continue
            }

            // Select "On My iPhone / iPad" directory, if necessary
            let location = app.staticTexts.matching(locationPredicate).firstMatch
            if location.wait(for: \.isHittable, toEqual: true, timeout: 2) {
                location.tap()
            }

            guard save.wait(for: \.isHittable, toEqual: true, timeout: 5) else {
                continue
            }
            save.tap()

            if app.staticTexts["Replace Existing Items?"].waitForExistence(timeout: 5) {
                #if os(visionOS)
                XCTFail("""
                On VisionOS, replacing files is very buggy, often leading to a complete freeze of the 'Save to Files' window.
                Please ensure that all already existing chat export files are deleted when executing the UI test.
                """)
                #endif
                guard app.buttons["Replace"].wait(for: \.isHittable, toEqual: true, timeout: 5) else {
                    continue
                }
                app.buttons["Replace"].tap()
            }

            // the share sheet dismissing and the app coming back is the observable end of the save
            guard app.staticTexts["GroveChat"].waitForExistence(timeout: 30) else {
                continue
            }

            // Launch the Files app
            guard filesApp.launchAndWait(timeout: 15) else {
                continue
            }

            // Handle already open files
            let done = filesApp.buttons["Done"].firstMatch
            if done.wait(for: \.isHittable, toEqual: true, timeout: 2) {
                done.tap()
            }

            // The Files app exposes more than one "Browse" control depending on OS version and
            // layout (tab bar plus sidebar). `waitForExistence` tolerates an ambiguous query but
            // `tap()` requires exactly one match, so resolve it before tapping.
            let browse = filesApp.buttons["Browse"].firstMatch
            if browse.wait(for: \.isHittable, toEqual: true, timeout: 5) {
                browse.tap()
            }
            let filesLocation = filesApp.staticTexts.matching(locationPredicate).firstMatch
            if filesLocation.wait(for: \.isHittable, toEqual: true, timeout: 5) {
                filesLocation.tap()
            }

            // Check if file exists - If not, try the export procedure again
            if filesApp.staticTexts["Exported Chat"].waitForExistence(timeout: 5) {
                break
            }
        }
        
        // Open File
        let exportedChat = filesApp.collectionViews["File View"].cells["Exported Chat, pdf"]
        XCTAssert(filesApp.staticTexts["Exported Chat"].waitForExistence(timeout: 5))
        XCTAssert(exportedChat.waitForExistence(timeout: 2))

        XCTAssert(exportedChat.images.firstMatch.waitForExistence(timeout: 2))
        XCTAssert(exportedChat.wait(for: \.isHittable, toEqual: true, timeout: 2))
        exportedChat.tap()
        
        // Check if PDF contains certain chat message
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "User Message!")
        #if os(visionOS)
        let fileView = XCUIApplication(bundleIdentifier: "com.apple.MRQuickLook")
        XCTAssert(fileView.otherElements.containing(predicate).firstMatch.waitForExistence(timeout: 5))
        #elseif os(iOS)
        if #available(iOS 26, *) {
            let preview = XCUIApplication(bundleIdentifier: "com.apple.Preview")
            guard preview.wait(for: .runningForeground, timeout: 3.0) else {
                throw XCTSkip("The Preview App seems to fail on iOS 26 simulators; please double-check with furhter updates and re-activate.")
            }
            XCTAssert(preview.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 10))
        } else {
            XCTAssert(filesApp.otherElements.containing(predicate).firstMatch.waitForExistence(timeout: 10))
            // Close File in Files App
            let closeFile = filesApp.buttons["Done"].firstMatch
            XCTAssert(closeFile.wait(for: \.isHittable, toEqual: true, timeout: 2))
            closeFile.tap()
        }
        #endif
    }
    
    func testChatSpeechOutput() throws {
        let app = XCUIApplication()
        
        #if os(macOS)
        let speakerButton = app.buttons["Speaker strikethrough"].firstMatch   // on macOS, need to match for first speaker that is found
        #else
        let speakerButton = app.buttons["Speaker strikethrough"]
        #endif

        XCTAssert(app.staticTexts["GroveChat"].waitForExistence(timeout: 1))
        XCTAssert(speakerButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
        XCTAssert(!app.buttons["Speaker"].waitForExistence(timeout: 2))

        speakerButton.tap()

        XCTAssert(!app.buttons["Speaker strikethrough"].waitForExistence(timeout: 2))
        XCTAssert(app.buttons["Speaker"].waitForExistence(timeout: 2))
    }
    
    func testFunctionCallAndResponse() throws {
        let app = XCUIApplication()
        
        XCTAssert(app.staticTexts["GroveChat"].waitForExistence(timeout: 1))
        XCTAssert(app.staticTexts["Assistant Message!"].waitForExistence(timeout: 1))
        
        try app.textFields["Message Input Textfield"].enter(value: "Call some function", options: [.disableKeyboardDismiss])
        XCTAssert(app.buttons["Send Message"].wait(for: \.isHittable, toEqual: true, timeout: 5))
        app.buttons["Send Message"].tap()

        // the test app replies three seconds after sending, then appends the response and the answer a second apart
        XCTAssert(app.staticTexts["call_test_func({ test: true })"].waitForExistence(timeout: 10))
        XCTAssert(app.staticTexts["{ some: response }"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["Assistant Message Response!"].waitForExistence(timeout: 5))
    }
}

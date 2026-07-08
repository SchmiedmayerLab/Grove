//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


@MainActor
class TestAppUITests: XCTestCase {
    private static let initialAssistantMessage = "**Assistant** Message!"
    private static let assistantMessageResponse = "**Assistant** Message Response!"

    @MainActor
    override func setUp() async throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--testMode"]
        app.launch()
    }
    
    
    func testChat() throws {
        let app = XCUIApplication()
        
        XCTAssert(app.staticTexts["SpeziChat"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts[Self.initialAssistantMessage].waitForExistence(timeout: 5))
        
        try app.textFields["Message Input Textfield"].enter(value: "User Message!", options: [.disableKeyboardDismiss])
        XCTAssert(app.buttons["Send Message"].waitForExistence(timeout: 5))
        app.buttons["Send Message"].tap()
        XCTAssert(app.staticTexts["User Message!"].waitForExistence(timeout: 5))
        XCTAssert(app.otherElements["Typing Indicator"].waitForExistence(timeout: 5))
        XCTAssert(app.otherElements["Typing Indicator"].waitForNonExistence(timeout: 15))
        XCTAssert(app.staticTexts[Self.assistantMessageResponse].waitForExistence(timeout: 5))
    }
    
    
    func testChatExport() throws {  // swiftlint:disable:this function_body_length
        // Skip chat export test on visionOS and macOS
        #if os(visionOS)
        throw XCTSkip("VisionOS is unstable and are skipped at the moment")
        #elseif os(macOS)
        throw XCTSkip("macOS export to a file is not possible (regular sharesheet is)")
        #endif

        let app = XCUIApplication()
        let filesApp = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        let maxAttempts = 10
        var lastRetryFailure = "Chat export did not complete."
        
        for attempt in 1...maxAttempts {
            app.launchArguments = ["--testMode"]
            app.launch()
            if let failure = try attemptChatExport(app: app, filesApp: filesApp, attempt: attempt) {
                lastRetryFailure = failure
            } else {
                lastRetryFailure = ""
                break
            }
        }
        
        // Open File
        XCTAssert(filesApp.staticTexts["Exported Chat"].waitForExistence(timeout: 10), lastRetryFailure)
        XCTAssert(filesApp.collectionViews["File View"].cells["Exported Chat, pdf"].waitForExistence(timeout: 10))
        
        XCTAssert(filesApp.collectionViews["File View"].cells["Exported Chat, pdf"].images.firstMatch.waitForExistence(timeout: 10))
        filesApp.collectionViews["File View"].cells["Exported Chat, pdf"].tap()
        
        // Check if PDF contains certain chat message
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "User Message!")
        #if os(visionOS)
        let fileView = XCUIApplication(bundleIdentifier: "com.apple.MRQuickLook")
        XCTAssert(fileView.otherElements.containing(predicate).firstMatch.waitForExistence(timeout: 5))
        #elseif os(iOS)
        if #available(iOS 26, *) {
            let preview = XCUIApplication(bundleIdentifier: "com.apple.Preview")
            XCTAssert(preview.wait(for: .runningForeground, timeout: 10.0), "Preview must open the exported chat PDF on iOS 26.")
            XCTAssert(preview.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 15))
        } else {
            XCTAssert(filesApp.otherElements.containing(predicate).firstMatch.waitForExistence(timeout: 15))
            // Close File in Files App
            XCTAssert(filesApp.buttons["Done"].waitForExistence(timeout: 5))
            filesApp.buttons["Done"].tap()
        }
        #endif
    }
    
    func testChatSpeechOutput() throws {
        let app = XCUIApplication()
        
        XCTAssert(app.staticTexts["SpeziChat"].waitForExistence(timeout: 5))
        XCTAssert(app.buttons["Speaker strikethrough"].waitForExistence(timeout: 2))
        XCTAssert(!app.buttons["Speaker"].waitForExistence(timeout: 2))

        #if os(macOS)
        app.buttons["Speaker strikethrough"].firstMatch.tap()   // on macOS, need to match for first speaker that is found
        #else
        app.buttons["Speaker strikethrough"].tap()
        #endif
        
        XCTAssert(!app.buttons["Speaker strikethrough"].waitForExistence(timeout: 2))
        XCTAssert(app.buttons["Speaker"].waitForExistence(timeout: 2))
    }
    
    func testFunctionCallAndResponse() throws {
        let app = XCUIApplication()
        
        XCTAssert(app.staticTexts["SpeziChat"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts[Self.initialAssistantMessage].waitForExistence(timeout: 5))
        
        try app.textFields["Message Input Textfield"].enter(value: "Call some function", options: [.disableKeyboardDismiss])
        XCTAssert(app.buttons["Send Message"].waitForExistence(timeout: 5))
        app.buttons["Send Message"].tap()
        
        sleep(5)
        
        XCTAssert(app.staticTexts["call_test_func({ test: true })"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts["{ some: response }"].waitForExistence(timeout: 5))
        XCTAssert(app.staticTexts[Self.assistantMessageResponse].waitForExistence(timeout: 5))
    }
}


extension TestAppUITests {
    private func attemptChatExport(app: XCUIApplication, filesApp: XCUIApplication, attempt: Int) throws -> String? {
        if let failure = try sendExportMessage(app: app, attempt: attempt) {
            return failure
        }
        if let failure = openSaveToFiles(app: app, attempt: attempt) {
            return failure
        }
        if let failure = saveExportedChat(app: app, attempt: attempt) {
            return failure
        }
        return exportedChatFailure(filesApp: filesApp, attempt: attempt)
    }

    private func sendExportMessage(app: XCUIApplication, attempt: Int) throws -> String? {
        if let failure = retryFailure(app.staticTexts["SpeziChat"].waitForExistence(timeout: 5), attempt, "chat screen did not appear") {
            return failure
        }
        if let failure = retryFailure(app.textFields["Message Input Textfield"].waitForExistence(timeout: 5), attempt, "message input did not appear") {
            return failure
        }
        try app.textFields["Message Input Textfield"].enter(value: "User Message!", options: [.disableKeyboardDismiss])
        if let failure = retryFailure(app.buttons["Send Message"].waitForExistence(timeout: 5), attempt, "send button did not appear") {
            return failure
        }
        app.buttons["Send Message"].tap()
        if let failure = retryFailure(app.staticTexts["User Message!"].waitForExistence(timeout: 5), attempt, "sent user message did not appear") {
            return failure
        }

        let typingIndicator = app.otherElements["Typing Indicator"]
        if typingIndicator.waitForExistence(timeout: 5),
           let failure = retryFailure(typingIndicator.waitForNonExistence(timeout: 15), attempt, "typing indicator did not disappear") {
            return failure
        }
        return retryFailure(
            app.staticTexts[Self.assistantMessageResponse].waitForExistence(timeout: 5),
            attempt,
            "assistant response did not appear"
        )
    }

    private func openSaveToFiles(app: XCUIApplication, attempt: Int) -> String? {
        if let failure = retryFailure(app.buttons["Export the Chat"].waitForExistence(timeout: 5), attempt, "export button did not appear") {
            return failure
        }
        app.buttons["Export the Chat"].tap()

        #if os(visionOS)
        if let failure = retryFailure(
            app.cells["XCElementSnapshotPrivilegedValuePlaceholder"].waitForExistence(timeout: 10),
            attempt,
            "unlabeled Save to Files cell did not appear"
        ) {
            return failure
        }
        app.cells["XCElementSnapshotPrivilegedValuePlaceholder"].tap()
        #else
        if let failure = retryFailure(app.staticTexts["Save to Files"].waitForExistence(timeout: 15), attempt, "Save to Files action did not appear") {
            return failure
        }
        sleep(1) // The action can exist while still animating into position; early taps can miss.
        app.staticTexts["Save to Files"].tap()
        #endif

        return nil
    }

    private func saveExportedChat(app: XCUIApplication, attempt: Int) -> String? {
        sleep(3)

        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", "On My")
        app.staticTexts.containing(predicate).allElementsBoundByIndex.first?.tap()

        if let failure = retryFailure(app.buttons["Save"].waitForExistence(timeout: 10), attempt, "Files save button did not appear") {
            return failure
        }
        app.buttons["Save"].tap()
        sleep(10)

        if app.staticTexts["Replace Existing Items?"].waitForExistence(timeout: 5) {
            #if os(visionOS)
            XCTFail("""
            On VisionOS, replacing files is very buggy, often leading to a complete freeze of the 'Save to Files' window.
            Please ensure that all already existing chat export files are deleted when executing the UI test.
            """)
            #endif
            if let failure = retryFailure(app.buttons["Replace"].waitForExistence(timeout: 5), attempt, "replace confirmation did not appear") {
                return failure
            }
            app.buttons["Replace"].tap()
            sleep(3)
        }

        return retryFailure(app.staticTexts["SpeziChat"].waitForExistence(timeout: 20), attempt, "share sheet did not close back to chat")
    }

    private func exportedChatFailure(filesApp: XCUIApplication, attempt: Int) -> String? {
        filesApp.launch()

        if filesApp.buttons["Done"].waitForExistence(timeout: 5) {
            filesApp.buttons["Done"].tap()
        }

        if filesApp.staticTexts["Exported Chat"].waitForExistence(timeout: 10) {
            return nil
        }
        return "Attempt \(attempt): exported file did not appear in Files."
    }

    private func retryFailure(_ condition: Bool, _ attempt: Int, _ message: String) -> String? {
        condition ? nil : "Attempt \(attempt): \(message)."
    }
}

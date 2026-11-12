//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import XCTest


/// Waits until `condition` holds, checking at once and then every tenth of a second.
///
/// XCTest's own waits — `waitForExistence(timeout:)`, `waitForNonExistence(timeout:)`,
/// `wait(for:toEqual:timeout:)`, `wait(for:timeout:)` on an app, and predicate expectations — first check about a
/// second in, even when the condition already holds, and then once a second. A UI test waits at almost every step,
/// and that second adds up to most of its run time. This one checks straight away.
///
/// That second also used to cover for an app finishing something it had scheduled for later — a page that moves
/// on shortly after an answer, a history that files a change once the pen has lifted. Wait for the thing the next
/// step needs, and use ``XCUIAutomation/XCUIElement/waitUntilSettled(timeout:)`` before touching something that
/// may still be moving.
///
/// ```swift
/// XCTAssert(waitUntil(timeout: 10) { app.staticTexts["All Done!"].exists })
/// XCTAssert(waitUntil(timeout: 2) { !app.keyboards.firstMatch.exists })
/// ```
///
/// Between checks the main run loop runs, as it does in XCTest's own waits, so a condition can depend on callbacks
/// the test process receives on the main thread.
///
/// - Parameters:
///   - timeout: How long to wait, in seconds.
///   - condition: What to wait for; evaluated again at every check.
/// - Returns: Whether `condition` held within the timeout.
@MainActor
@discardableResult
public func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date.now.addingTimeInterval(timeout)
    while !condition() {
        guard Date.now < deadline else {
            return false
        }
        let pause = min(Date.now.addingTimeInterval(0.1), deadline)
        while Date.now < pause, RunLoop.current.run(mode: .default, before: pause) {}
        // A run loop with nothing to run returns at once; the pause still has to be taken.
        if Date.now < pause {
            Thread.sleep(until: pause)
        }
    }
    return true
}


extension XCUIElement {
    /// Waits until the element is on screen and has stopped moving: in the same place at two checks in a row.
    ///
    /// XCTest waits for the app to go idle around each interaction, but not for movement the app starts a moment
    /// later — a page that scrolls on to the next question after an answer, a sheet an app presents from a task.
    /// A tap made then lands where the control used to be.
    ///
    /// - Parameter timeout: How long to wait, in seconds.
    /// - Returns: Whether the element came to rest within the timeout.
    @discardableResult
    public func waitUntilSettled(timeout: TimeInterval) -> Bool {
        var lastFrame: CGRect?
        return waitUntil(timeout: timeout) {
            // One snapshot reads existence and frame together, so an element that goes away in between is no failure.
            let frame = (try? snapshot())?.frame
            defer {
                lastFrame = frame
            }
            return frame != nil && frame == lastFrame
        }
    }
}

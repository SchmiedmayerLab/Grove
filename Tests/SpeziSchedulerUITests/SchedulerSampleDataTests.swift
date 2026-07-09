//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziFoundation
@_spi(TestingSupport)
import SpeziScheduler
@_spi(TestingSupport)
@testable import SpeziSchedulerUI
import SpeziTesting
import XCTest


@available(iOS 18, macOS 15, watchOS 11, visionOS 2, *)
final class SchedulerSampleDataTests: XCTestCase {
    @MainActor
    func testSchedulerSampleData() throws {
        let container = try SchedulerSampleData.makeSharedContext()

        let scheduler = Scheduler(persistence: .testingContainer(container))
        SpeziTesting.withDependencyResolution {
            scheduler
        }

        let results = try scheduler.queryTasks(for: Date.yesterday..<Date.tomorrow)
        XCTAssertEqual(results.count, 1, "Received unexpected amount of tasks in query.")

        let events = try scheduler.queryEvents(for: Date.yesterday..<Date.tomorrow)
        XCTAssertEqual(events.count, 1, "Received unexpected amount of events in query.")
    }
}

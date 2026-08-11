//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable force_try

import Foundation
import GroveFoundation
import Testing


@Suite
struct ManagedTaskQueueTests {
    @MainActor
    private final class OperationsTracker: Sendable {
        struct Operation: Hashable {
            let id: Int
            let startDate: Date
            let endDate: Date
            
            var timeRange: Range<Date> {
                startDate..<endDate
            }
            
            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.id == rhs.id
            }
            func hash(into hasher: inout Hasher) {
                hasher.combine(id)
            }
        }
        
        let expectedLimit: Int
        private(set) var active = Set<Operation>()
        private(set) var completed = Set<Operation>()
        private(set) var maxObservedConcurrency = 0
        
        var activeIds: Set<Int> {
            active.mapIntoSet(\.id)
        }
        var completedIds: Set<Int> {
            completed.mapIntoSet(\.id)
        }
        
        nonisolated init(expectedLimit: Int) {
            self.expectedLimit = expectedLimit
        }
        
        func trackBegin(of operationId: Int) throws {
            #expect(
                active.count < expectedLimit,
                "adding \(operationId); active: \(activeIds.sorted()); completed: \(completedIds.sorted())"
            )
            try #require(!completed.contains { $0.id == operationId }, "Operation '\(operationId)' has already run")
            try #require(active.insert(.init(id: operationId, startDate: .now, endDate: .distantFuture)).inserted, "Operation '\(operationId)' is already running")
            maxObservedConcurrency = max(maxObservedConcurrency, active.count)
        }
        
        func trackEnd(of operationId: Int) throws {
            #expect(
                active.count <= expectedLimit,
                "removing \(operationId); active: \(activeIds.sorted()); completed: \(completedIds.sorted())"
            )
            try #require(!completed.contains { $0.id == operationId }, "Operation '\(operationId)' has already run")
            let idx = try #require(active.firstIndex { $0.id == operationId }, "Operation '\(operationId)' is not running")
            let operation = active.remove(at: idx)
            completed.insert(.init(id: operation.id, startDate: operation.startDate, endDate: .now))
        }
    }
    
    
    @Test(arguments: Array(1...17))
    func managedTaskQueue(concurrencyLimit: Int) async {
        let numTasks = concurrencyLimit * 3
        let tracker = OperationsTracker(expectedLimit: concurrencyLimit)
        await withManagedTaskQueue(limit: concurrencyLimit) { taskQueue in
            for idx in 0..<numTasks {
                taskQueue.addTask {
                    try! await tracker.trackBegin(of: idx)
                    try! await Task.sleep(for: .seconds(0.25))
                    try! await tracker.trackEnd(of: idx)
                }
            }
        }
        #expect(await tracker.active.isEmpty)
        #expect(await tracker.completedIds == Set(0..<numTasks))
        #expect(await tracker.maxObservedConcurrency <= concurrencyLimit)
    }
    
    
    @Test(arguments: Array(1...20))
    func ordering2(limit: Int) async throws {
        let tracker = OperationsTracker(expectedLimit: limit)
        await withManagedTaskQueue(limit: limit) { taskQueue in
            for idx in 0..<(limit * 3) {
                taskQueue.addTask {
                    try! await tracker.trackBegin(of: idx)
                    try! await Task.sleep(for: .seconds(2))
                    try! await tracker.trackEnd(of: idx)
                }
            }
        }
        let operations = await tracker.completed.sorted(using: [
            KeyPathComparator(\.startDate),
            KeyPathComparator(\.id)
        ])
        
        for operation in operations {
            let midpoint = operation.startDate.addingTimeInterval(operation.endDate.timeIntervalSince(operation.startDate) / 2)
            let numActiveTasks = operations.count { $0.timeRange.contains(midpoint) }
            let expectedRange = (limit - 1)...limit
            #expect(
                expectedRange.contains(numActiveTasks),
                "At midpoint of operation \(operation.id), expected \(expectedRange) active tasks; got \(numActiveTasks) (all task logging: \(operations))"
            )
        }
    }
}

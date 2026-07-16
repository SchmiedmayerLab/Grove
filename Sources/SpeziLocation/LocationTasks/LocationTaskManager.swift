//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreLocation
import Foundation


/// Manages tasks that handle events from the `CLLocationManagerDelegate`
final class LocationTaskManager: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [any LocationTask] = []
    
    /// Adds a new task
    /// - Parameter task: A task conforming to `LocationTask`
    func add(_ task: any LocationTask) {
        lock.withLock {
            tasks.append(task)
        }
    }
    
    /// Removes a task
    /// - Parameter task: A task conforming to `LocationTask`
    func remove(_ task: any LocationTask) {
        remove(id: task.id)
    }

    /// Removes a task with the provided identifier.
    /// - Parameter id: The identifier of the task to remove.
    func remove(id: UUID) {
        lock.withLock {
            tasks.removeAll { $0.id == id }
        }
    }
    
    /// Notifies all tasks of events received from `CLLocationManagerDelegate`.
    /// - Parameter event: The relevant `LocationManagerEvent`
    func notify(_ event: LocationManagerEvent) {
        let currentTasks = lock.withLock { self.tasks }
        currentTasks.forEach {
            $0.process(event: event)
        }
    }
}

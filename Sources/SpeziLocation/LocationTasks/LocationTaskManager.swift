//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreLocation


/// Manages tasks that handle events from the `CLLocationManagerDelegate`
final class LocationTaskManager {
    private var tasks: [any LocationTask] = []
    
    /// Adds a new task
    /// - Parameter task: A task conforming to `LocationTask`
    func add(_ task: any LocationTask) {
        tasks.append(task)
    }
    
    /// Removes a task
    /// - Parameter task: A task conforming to `LocationTask`
    func remove(_ task: any LocationTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.remove(at: index)
        }
    }
    
    /// Notifies all tasks of events received from `CLLocationManagerDelegate`.
    /// - Parameter event: The relevant `LocationManagerEvent`
    func notify(_ event: LocationManagerEvent) {
        tasks.forEach {
            $0.process(event: event)
        }
    }
}

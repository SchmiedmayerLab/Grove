//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A protocol for creating objects for managing events from `CLLocationManagerDelegate`
public protocol LocationTask {
    /// A unique identifier representing this task
    var id: UUID { get }
    
    /// Processes an event received from the `CLLocationManager`
    /// - Parameter event: The relevant `LocationManagerEvent`
    func process(event: LocationManagerEvent)
}

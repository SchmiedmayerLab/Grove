//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


public import CoreLocation
import Foundation


/// Defines the types of updates that can be received from the location manager.
public enum LocationUpdateEvent {
    /// Represents an event where new location data is available.
    /// - Parameter locations: An array of `CLLocation` objects.
    /// This case is used when the location manager has new location data to provide.
    case updatedLocations(_ locations: [CLLocation])
    
    /// Represents an event where an error occurred in receiving location data.
    /// - Parameter error: An `Error` object that describes what went wrong.
    /// This case is used when there is an error in location updates, such as when access is denied or the hardware is not functioning correctly.
    case error(_ error: Error)
    
    /// An array of `CLLocation` objects representing an updated set of location data received from `CoreLocation`. The array will always contain the current location, but may have additional values if updates were deferred, organized in the order in which they occurred. The latest location is always at the end of the array.
    public var locations: [CLLocation] {
        if case .updatedLocations(let locations) = self {
            return locations
        }
        return []
    }
    
    /// An `Error`, if received from the location manager.
    public var error: Error? {
        if case .error(let error) = self {
            return error
        }
        return nil
    }
}

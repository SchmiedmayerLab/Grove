//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CoreLocation
public import Foundation


/// A task for getting the user's current location
public class GetLocationTask: LocationTask {
    /// A unique identifier for the task, generated using UUID.
    public let id = UUID()
    
    /// An optional continuation used to handle asynchronous location updates or errors.
    private var continuation: CheckedContinuation<LocationUpdateEvent, any Error>?
    
    /// A weak reference to a `SpeziLocation` component, used to interact with location services.
    private weak var component: SpeziLocation?

    /// Initializes a new `GetLocationTask` with a given `SpeziLocation` component.
    /// - Parameter component: The `SpeziLocation` component used for accessing location services.
    init(component: SpeziLocation) {
        self.component = component
    }

    /// Asynchronously requests the user's current location. This method can throw an error if the `SpeziLocation` component is not found.
    /// - Returns: A `LocationUpdateEvent` representing the latest location update or an error event.
    /// - Throws: `LocationError.componentNotFound` if the `SpeziLocation` component is not available.
    public func getLocation() async throws -> LocationUpdateEvent {
        guard let component else {
            throw LocationError.componentNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            component.taskManager.add(self)
            self.continuation = continuation
            component.locationManager.requestLocation()
        }
    }

    /// Processes location manager events. This method updates the continuation with new location data or an error.
    /// - Parameter event: A `LocationManagerEvent` representing the event to process.
    public func process(event: LocationManagerEvent) {
        guard let component, let continuation else {
            return
        }
        
        switch event {
        case let .updatedLocations(locations: locations):
            continuation.resume(returning: .updatedLocations(locations))
            component.taskManager.remove(self)
        case let .didFailWithError(error):
            continuation.resume(returning: .error(error))
            component.taskManager.remove(self)
        default:
            break
        }
    }
    
    /// Cancels the current location task, effectively nullifying the continuation.
    public func cancel() {
        continuation = nil
    }
}

//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


public import CoreLocation
public import Foundation


/// `LocationAuthorizationTask` is a class that conforms to the `LocationTask` protocol. It is designed to manage the process of requesting and handling location authorization from the user. This class interacts with `SpeziLocation` component to request and monitor changes in location authorization status.
public class LocationAuthorizationTask: LocationTask {
    /// A unique identifier for the task, generated using UUID.
    public let id = UUID()
    
    /// A continuation used to asynchronously handle the response to authorization requests.
    private var continuation: CheckedContinuation<CLAuthorizationStatus, any Error>?
    
    /// A weak reference to the `SpeziLocation` component, responsible for accessing and managing location services.
    private weak var component: SpeziLocation?

    /// Initializes a new `LocationAuthorizationTask` with a given `SpeziLocation` component.
    /// - Parameter component: The `SpeziLocation` component used for handling location authorization.
    init(component: SpeziLocation) {
        self.component = component
    }

    /// Asynchronously requests permission from the user to always access their location. This method can throw an error if the `SpeziLocation` component is not found.
    /// - Returns: The current `CLAuthorizationStatus`.
    /// - Throws: `LocationError.componentNotFound` if the `SpeziLocation` component is not available.
    public func requestAlwaysAuthorization() async throws -> CLAuthorizationStatus {
        guard let component else {
            throw LocationError.componentNotFound
        }
        
        let status = component.locationManager.authorizationStatus
        
        return try await withCheckedThrowingContinuation { continuation in
            if status == .notDetermined || status == .authorizedWhenInUse {
                continuation.resume(with: .success(status))
            } else {
                self.continuation = continuation
                component.taskManager.add(self)
                component.locationManager.requestAlwaysAuthorization()
            }
        }
    }

    /// Asynchronously requests permission from the user to access their location when the app is in use. This method can throw an error if the `SpeziLocation` component is not found.
    /// - Returns: The current `CLAuthorizationStatus`.
    /// - Throws: `LocationError.componentNotFound` if the `SpeziLocation` component is not available.
    public func requestWhenInUseAuthorization() async throws -> CLAuthorizationStatus {
        guard let component else {
            throw LocationError.componentNotFound
        }
        
        let status = component.locationManager.authorizationStatus
        
        return try await withCheckedThrowingContinuation { continuation in
            if status != .notDetermined {
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                component.taskManager.add(self)
                component.locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    /// Processes location manager events related to authorization changes. It updates the continuation with the new authorization status.
    /// - Parameter event: A `LocationManagerEvent` representing the event to process.
    public func process(event: LocationManagerEvent) {
        guard let component else {
            return
        }
        
        switch event {
        case .changedAuthorization(let authorizationStatus):
            continuation?.resume(returning: authorizationStatus)
            component.taskManager.remove(self)
        default:
            break
        }
    }

    /// Cancels the current authorization request task, effectively nullifying the continuation.
    public func cancel() {
        continuation = nil
    }
}

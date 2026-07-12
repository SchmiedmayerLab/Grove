//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import CoreLocation
import Foundation
import Spezi


public final class SpeziLocation: Module, DefaultInitializable, EnvironmentAccessible {
    /// The `CLLocationManager` instance used for all location services.
    private(set) var locationManager: CLLocationManager
    
    /// The `LocationDelegate` instance used to handle callbacks from the location manager.
    private(set) var locationDelegate: LocationDelegate? // swiftlint:disable:this weak_delegate
    
    /// The `LocationTaskManager` instance used to manage location-related tasks.
    private(set) var taskManager: LocationTaskManager
    
    /// Initializes a new instance of `SpeziLocation`. It sets up the location manager and its delegate.
    public init() {
        self.locationManager = CLLocationManager()
        self.taskManager = LocationTaskManager()
        self.locationDelegate = LocationDelegate(taskManager: self.taskManager)
        self.locationManager.delegate = locationDelegate
    }

    /// Asynchronously requests location authorization from the user when the app is in use.
    /// - Returns: The current `CLAuthorizationStatus`.
    /// - Throws: An error if the authorization request fails.
    @MainActor
    public func requestWhenInUseAuthorization() async throws -> CLAuthorizationStatus {
        let task = LocationAuthorizationTask(component: self)
        let taskID = task.id
        let taskManager = self.taskManager
        return try await withTaskCancellationHandler {
            try await task.requestWhenInUseAuthorization()
        } onCancel: {
            taskManager.remove(id: taskID)
        }
    }
    
    /// Asynchronously requests always-on location authorization from the user.
    /// - Returns: The current `CLAuthorizationStatus`.
    /// - Throws: An error if the authorization request fails.
    @MainActor
    public func requestAlwaysAuthorization() async throws -> CLAuthorizationStatus {
        let task = LocationAuthorizationTask(component: self)
        let taskID = task.id
        let taskManager = self.taskManager
        return try await withTaskCancellationHandler {
            try await task.requestAlwaysAuthorization()
        } onCancel: {
            taskManager.remove(id: taskID)
        }
    }
    
    /// Asynchronously retrieves the most recent location of the user.
    /// - Returns: A `CLLocation` or `nil` if no location is available.
    /// - Throws: An error if the location request fails
    @MainActor
    public func getLatestLocation() async throws -> CLLocation? {
        try await self.getLatestLocations().last
    }

    /// Asynchronously retrieves the most recent location(s) of the user.
    /// - Returns: An array of the latest `CLLocation`s, or `nil` if no location is available. More than one location may be returned. The locations are ordered by timestamp with the most recent at the end.
    /// - Throws: An error if the location request fails.
    @MainActor
    public func getLatestLocations() async throws -> [CLLocation] {
        let task = GetLocationTask(component: self)
        let taskID = task.id
        let taskManager = self.taskManager
        let event = try await withTaskCancellationHandler {
            try await task.getLocation()
        } onCancel: {
            taskManager.remove(id: taskID)
        }
        return event.locations
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreLocation


/// `LocationDelegate` is a subclass of `NSObject` that conforms to the `CLLocationManagerDelegate` protocol. It serves as a delegate for `CLLocationManager` to handle location updates and errors. This class is designed to work in conjunction with a `LocationTaskManager` to propagate location-related events.
public class LocationDelegate: NSObject, CLLocationManagerDelegate {
    /// A weak reference to a `LocationTaskManager`. This reference is used to notify the task manager about location events.
    private weak var taskManager: LocationTaskManager?

    /// Initializes a new instance of `LocationDelegate` with a reference to a `LocationTaskManager`.
    /// - Parameter taskManager: The `LocationTaskManager` that will be notified of location events.
    init(taskManager: LocationTaskManager) {
        self.taskManager = taskManager
        super.init()
    }

    /// Called by the system when new location data is available. Notifies the task manager about the updated locations.
    /// - Parameters:
    ///   - manager: The location manager object that generated the update event.
    ///   - locations: An array of `CLLocation` objects containing the new location data.
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        taskManager?.notify(.updatedLocations(locations: locations))
    }

    /// Called by the system when the location manager encounters an error while trying to get location data. Notifies the task manager about the error.
    /// - Parameters:
    ///   - manager: The location manager object that encountered the error.
    ///   - error: The error object containing the reason why location data could not be retrieved.
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        taskManager?.notify(.didFailWithError(error))
    }
    
    /// Called by the system when there is a change in the location manager’s authorization or accuracy authorization status. Notifies the task manager about the changes.
    /// - Parameter manager: The location manager object that reported the change in authorization status.
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        taskManager?.notify(.changedAccuracyAuthorization(manager.accuracyAuthorization))
        taskManager?.notify(.changedAuthorization(manager.authorizationStatus))
    }
}

//
// This source file is part of the SpeziLocation open source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreLocation
import Foundation


/// Encapsulates different types of events or updates that can occur in the context of location tracking, such as changes in authorization status, updates in location, or errors.
public enum LocationManagerEvent {
    /// Event for when the authorization status for accessing location services changes.
    /// - Parameter status: A `CLAuthorizationStatus` value indicating the new authorization status.
    /// This case is used when the app's authorization to use location services changes, for example, when a user grants or revokes location permissions.
    case changedAuthorization(_ status: CLAuthorizationStatus)
    
    /// Event for when the accuracy authorization for the location services changes.
    /// - Parameter authorization: A `CLAccuracyAuthorization` value indicating the new accuracy authorization.
    /// This case is relevant for iOS 14 and later, where users can choose to provide apps with reduced accuracy location data.
    case changedAccuracyAuthorization(_ authorization: CLAccuracyAuthorization)
    
    /// Event for when new location data is available.
    /// - Parameter locations: An array of `CLLocation` objects representing the updated location data.
    /// This case is used when there are updates to the location data, providing an array of `CLLocation` objects with the new data.
    case updatedLocations(locations: [CLLocation])
    
    /// Event for when an error occurs while updating locations.
    /// - Parameter error: An `Error` object that provides details about the error.
    /// This case is used when there is an error during location updates, such as failure to retrieve location data or hardware-related issues.
    case didFailWithError(_ error: any Error)
}

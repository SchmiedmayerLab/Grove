//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

private import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// Indicates that a SensorKit operation failed because the SensorKit framework is not available.
    public struct UnavailableError: Error {
        @inlinable
        internal init() {}
    }
    
    /// Whether SensorKit is available on the device.
    ///
    /// - Important: If this value is `false`, `SensorKit.framework` is missing on this device, and **none** of the sensor-related APIs should be used!
    public static let isAvailable: Bool = {
        Bundle(identifier: "com.apple.SensorKit") != nil
    }()
    
    
    /// Verifies that the SensorKit framework is available, and throws an ``UnavailableError`` if not.
    @inlinable
    static func assertIsAvailable() throws(UnavailableError) {
        if !isAvailable {
            throw UnavailableError()
        }
    }
}

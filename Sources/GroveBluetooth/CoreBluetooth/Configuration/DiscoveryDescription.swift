//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Description of a device discovery strategy.
///
/// This type describes how to discover a device and what services and characteristics
/// to expect.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct DiscoveryDescription {
    /// The criteria by which we identify a discovered device.
    public let discoveryCriteria: DiscoveryCriteria
    /// Description of the device.
    ///
    /// Provides guidance how and what to discover of the bluetooth peripheral.
    public let device: DeviceDescription


    /// Create a new discovery configuration for a given type of device.
    /// - Parameters:
    ///   - discoveryCriteria: The criteria by which we identify a discovered device.
    ///   - device: The description of the device.
    public init(discoverBy discoveryCriteria: DiscoveryCriteria, device: DeviceDescription) {
        self.discoveryCriteria = discoveryCriteria
        self.device = device
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension DiscoveryDescription: Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension DiscoveryDescription: Identifiable {
    public var id: DiscoveryCriteria {
        discoveryCriteria
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension DiscoveryDescription: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(discoveryCriteria)
    }
}

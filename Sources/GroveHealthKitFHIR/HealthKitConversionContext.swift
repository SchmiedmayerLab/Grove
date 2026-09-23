//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
public import GroveFHIRContract
public import HealthKit


/// Names the physical unit behind a sample's `HKDevice`, or declines when no stable token exists.
public protocol RecordingDeviceResolver: Sendable {
    func recordingDevice(for device: HKDevice) -> RecordingDevice?
}


/// HealthKit's per-unit `HKDevice.localIdentifier`, when the source supplies one.
///
/// Model and version facts cannot identify a physical unit, so a device without the local
/// identifier yields no recording device and the conversion reports the omission.
public struct HealthKitLocalIdentifierResolver: RecordingDeviceResolver {
    public init() {}

    public func recordingDevice(for device: HKDevice) -> RecordingDevice? {
        guard let token = device.localIdentifier?.nonBlank else {
            return nil
        }
        return try? RecordingDevice(
            stableUnitToken: token,
            name: device.name?.nonBlank,
            manufacturer: device.manufacturer?.nonBlank,
            modelNumber: device.model?.nonBlank
        )
    }
}


/// The HealthKit-specific choices of one conversion; every disclosure defaults to omission.
public struct HealthKitConversionOptions: Sendable {
    /// Every policy omits.
    public static let `default` = Self()

    public var writer: HealthKitWriter
    public var recordingDevice: any RecordingDeviceResolver
    public var udiDisclosure: HealthKitUDIDisclosurePolicy
    public var routeDisclosure: RouteDisclosurePolicy
    public var nativeIdentifierDisclosure: GovernedSourceIdentifierDisclosurePolicy

    public init(
        writer: HealthKitWriter = .application,
        recordingDevice: any RecordingDeviceResolver = .healthKitLocalIdentifier,
        udiDisclosure: HealthKitUDIDisclosurePolicy = .omit,
        routeDisclosure: RouteDisclosurePolicy = .omit,
        nativeIdentifierDisclosure: GovernedSourceIdentifierDisclosurePolicy = .omit
    ) {
        self.writer = writer
        self.recordingDevice = recordingDevice
        self.udiDisclosure = udiDisclosure
        self.routeDisclosure = routeDisclosure
        self.nativeIdentifierDisclosure = nativeIdentifierDisclosure
    }
}


/// The shared event context plus HealthKit's own options. See <doc:ConfiguringAConversion>.
public struct HealthKitConversionContext: Sendable {
    public let event: ExchangeEventContext
    public let options: HealthKitConversionOptions

    var identityScope: OpaqueIdentityScope { event.identityScope }
    var eventIdentifier: ExchangeEventIdentifier { event.event }
    var repositoryScope: BusinessIdentifier { event.repositoryScope }
    var entryNodeIdentifierSystem: IdentifierSystem { event.entryNodeIdentifierSystem }
    var conversionInstant: Date { event.conversionInstant }
    var subjectIdentifier: BusinessIdentifier { event.subject.identifier }

    public init(event: ExchangeEventContext, options: HealthKitConversionOptions = .default) {
        self.event = event
        self.options = options
    }

    func repositoryID(_ node: ExchangeGraphNode) -> RepositoryID? {
        event.repositoryIDs[node]
    }
}


extension RecordingDeviceResolver where Self == HealthKitLocalIdentifierResolver {
    /// The default resolver: HealthKit's per-unit `HKDevice.localIdentifier`.
    public static var healthKitLocalIdentifier: Self { Self() }
}


extension String {
    var nonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

#endif

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


/// The application, host and source-device facts first used to convert one SensorKit batch.
/// Persist the encoded snapshot before conversion and reuse it on retry. Account authority,
/// study policy and identity secrets remain the caller's responsibility.
public struct SensorKitBatchSnapshot: Hashable, Sendable {
    public enum SnapshotError: Error, Equatable, Sendable {
        case unsupportedVersion
        case invalidFacts
        case capacityExceeded
    }

    public let application: ApplicationDevice
    public let host: HostDevice
    public let recordingDevice: RecordingDevice?
    public let sourceDevices: [RecordingDevice]
    public let sourceDevicesSuppliedEverySample: Bool
    public let sourceTimeZone: TimeZone
    public let conversionInstant: Date

    public init(
        application: ApplicationDevice,
        host: HostDevice,
        recordingDevice: RecordingDevice?,
        sourceDevices: [RecordingDevice] = [],
        sourceDevicesSuppliedEverySample: Bool = false,
        sourceTimeZone: TimeZone,
        conversionInstant: Date
    ) throws {
        guard sourceDevices.count <= 128,
              (0...253_402_300_799).contains(conversionInstant.timeIntervalSince1970),
              !sourceDevicesSuppliedEverySample || !sourceDevices.isEmpty,
              let zone = TimeZone(identifier: sourceTimeZone.identifier) else {
            throw SnapshotError.invalidFacts
        }
        self.application = application
        self.host = host
        self.recordingDevice = recordingDevice
        self.sourceDevices = sourceDevices
        self.sourceDevicesSuppliedEverySample = sourceDevicesSuppliedEverySample
        self.sourceTimeZone = zone
        self.conversionInstant = conversionInstant
        try representation.validateStringBounds()
    }

    /// Bounds input before decoding and reconstructs application/host values through their validated initializers.
    public init(encoded data: Data, maximumByteCount: Int) throws {
        guard maximumByteCount > 0, !data.isEmpty, data.count <= maximumByteCount else {
            throw SnapshotError.capacityExceeded
        }
        let value = try JSONDecoder().decode(Representation.self, from: data)
        guard value.version == 1 else { throw SnapshotError.unsupportedVersion }
        try value.validateStringBounds()
        guard let zone = TimeZone(identifier: value.timeZone) else { throw SnapshotError.invalidFacts }
        try self.init(
            application: value.application.value(),
            host: value.host.value(),
            recordingDevice: value.recording?.value,
            sourceDevices: value.sources.map(\.value),
            sourceDevicesSuppliedEverySample: value.sourcesSuppliedEverySample,
            sourceTimeZone: zone,
            conversionInstant: value.instant
        )
    }

    /// Encodes the exact retained facts. No device lookup or current-time fallback occurs.
    public func encoded(maximumByteCount: Int) throws -> Data {
        guard maximumByteCount > 0 else { throw SnapshotError.capacityExceeded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(representation)
        guard data.count <= maximumByteCount else { throw SnapshotError.capacityExceeded }
        return data
    }
}

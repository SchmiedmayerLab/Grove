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
///
/// Persist the encoded snapshot before the first conversion and convert a retry with the decoded snapshot, so both
/// state the same facts. Account authority, study policy and identity secrets remain the caller's responsibility.
public struct SensorKitBatchSnapshot: Hashable, Sendable {
    /// Why a snapshot could not be created, decoded or encoded.
    public enum SnapshotError: Error, Equatable, Sendable {
        /// The encoded snapshot has a version this release doesn't read.
        case unsupportedVersion
        /// A fact is invalid, such as an unknown time zone or a conversion instant outside the FHIR range.
        case invalidFacts
        /// The snapshot exceeds a byte limit, more than 128 source devices or 2,048 UTF-8 bytes in one string.
        case capacityExceeded
    }

    /// The application that converts the batch.
    public let application: ApplicationDevice
    /// The device that runs the application.
    public let host: HostDevice
    /// The device that recorded the batch, if known.
    public let recordingDevice: RecordingDevice?
    /// The source devices SensorKit named for the batch's samples.
    public let sourceDevices: [RecordingDevice]
    /// Whether SensorKit named a source device for every sample.
    public let sourceDevicesSuppliedEverySample: Bool
    /// The time zone of the source.
    public let sourceTimeZone: TimeZone
    /// The instant of the first conversion.
    public let conversionInstant: Date

    /// Creates a snapshot of the facts of a batch's first conversion.
    ///
    /// - Throws: ``SnapshotError/capacityExceeded`` for more than 128 source devices or a string of more than 2,048
    ///   UTF-8 bytes, and ``SnapshotError/invalidFacts`` for an unknown time zone, a conversion instant outside the
    ///   FHIR range, or source devices said to supply every sample when there are none.
    public init(
        application: ApplicationDevice,
        host: HostDevice,
        recordingDevice: RecordingDevice?,
        sourceDevices: [RecordingDevice] = [],
        sourceDevicesSuppliedEverySample: Bool = false,
        sourceTimeZone: TimeZone,
        conversionInstant: Date
    ) throws(SnapshotError) {
        guard sourceDevices.count <= 128 else {
            throw .capacityExceeded
        }
        guard (0...253_402_300_799).contains(conversionInstant.timeIntervalSince1970),
              !sourceDevicesSuppliedEverySample || !sourceDevices.isEmpty,
              let zone = TimeZone(identifier: sourceTimeZone.identifier) else {
            throw .invalidFacts
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

    /// Decodes a snapshot that ``encoded(maximumByteCount:)`` encoded.
    ///
    /// The byte limit is checked before decoding, and the application and host are validated as their initializers
    /// validate them.
    ///
    /// - Parameters:
    ///   - data: The encoded snapshot.
    ///   - maximumByteCount: The most bytes the encoded snapshot may hold.
    /// - Throws: ``SnapshotError/capacityExceeded`` for an empty or oversized snapshot or string,
    ///   ``SnapshotError/unsupportedVersion`` for another version, and ``SnapshotError/invalidFacts`` for bytes that
    ///   don't decode or facts that are invalid.
    public init(encoded data: Data, maximumByteCount: Int) throws(SnapshotError) {
        guard maximumByteCount > 0, !data.isEmpty, data.count <= maximumByteCount else {
            throw .capacityExceeded
        }
        // The version decides the shape, so it is read first: another version need not decode as this one.
        struct Version: Decodable {
            let version: Int
        }
        let value: Representation
        do {
            guard try JSONDecoder().decode(Version.self, from: data).version == 1 else { throw SnapshotError.unsupportedVersion }
            value = try JSONDecoder().decode(Representation.self, from: data)
        } catch SnapshotError.unsupportedVersion {
            throw .unsupportedVersion
        } catch {
            throw .invalidFacts
        }
        try value.validateStringBounds()
        guard let zone = TimeZone(identifier: value.timeZone) else { throw .invalidFacts }
        let application: ApplicationDevice
        let host: HostDevice
        do {
            application = try value.application.value()
            host = try value.host.value()
        } catch {
            throw .invalidFacts
        }
        try self.init(
            application: application,
            host: host,
            recordingDevice: value.recording?.value,
            sourceDevices: value.sources.map(\.value),
            sourceDevicesSuppliedEverySample: value.sourcesSuppliedEverySample,
            sourceTimeZone: zone,
            conversionInstant: value.instant
        )
    }

    /// Encodes the exact retained facts, without any device lookup or current-time fallback.
    ///
    /// - Throws: ``SnapshotError/capacityExceeded`` when the encoding exceeds `maximumByteCount`, and
    ///   ``SnapshotError/invalidFacts`` if the facts can't be encoded.
    public func encoded(maximumByteCount: Int) throws(SnapshotError) -> Data {
        guard maximumByteCount > 0 else { throw .capacityExceeded }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(representation)
        } catch {
            throw .invalidFacts
        }
        guard data.count <= maximumByteCount else { throw .capacityExceeded }
        return data
    }
}

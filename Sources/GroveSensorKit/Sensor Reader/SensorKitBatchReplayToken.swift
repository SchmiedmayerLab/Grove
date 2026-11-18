//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// Bounded durable evidence for fetching one previously allocated batch again.
    /// The caller must retain and verify ordered content digests: SensorKit can expire or change native history.
    /// Replaying this token never reads, resets or advances the live acquisition cursor.
    public struct BatchReplayToken: Sendable, Equatable {
        private struct Representation: Codable, Sendable, Equatable {
            let version: Int
            let sensorIdentifier: String
            let deviceProductType: String
            let anchor: QueryAnchor
        }

        private let representation: Representation
        /// The identifier of the sensor the batch was fetched from.
        public var sensorIdentifier: String { representation.sensorIdentifier }
        /// The product type of the device the batch was fetched from.
        public var deviceProductType: String { representation.deviceProductType }
        /// The acquisition coordinate the batch was allocated, which a replay of the batch states again.
        public var acquisitionBatch: AcquisitionBatchCoordinate { representation.anchor.acquisitionBatchCoordinate }
        var anchor: QueryAnchor { representation.anchor }

        init(sensorIdentifier: String, deviceProductType: String, anchor: QueryAnchor) throws(BatchReplayError) {
            representation = Representation(version: 1, sensorIdentifier: sensorIdentifier, deviceProductType: deviceProductType, anchor: anchor)
            try validate()
        }

        /// Reconstructs only the bounded, versioned replay representation emitted by this module.
        ///
        /// - Parameter encoded: The bytes of ``encoded()``, at most 16 KiB.
        /// - Throws: ``BatchReplayError/invalidToken`` for any other bytes.
        public init(encoded: Data) throws(BatchReplayError) {
            guard (1...16_384).contains(encoded.count) else { throw .invalidToken }
            do {
                representation = try JSONDecoder().decode(Representation.self, from: encoded)
            } catch {
                throw .invalidToken
            }
            try validate()
        }

        /// Encodes the exact pending anchor, including its unchanged acquisition-coordinate identity.
        public func encoded() throws -> Data {
            try validate()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(representation)
            guard data.count <= 16_384 else { throw BatchReplayError.invalidToken }
            return data
        }

        private func validate() throws(BatchReplayError) {
            guard representation.version == 1,
                  (1...512).contains(sensorIdentifier.utf8.count), !sensorIdentifier.utf8.contains(0),
                  (1...256).contains(deviceProductType.utf8.count), !deviceProductType.utf8.contains(0),
                  anchor.timestamp.timeIntervalSinceReferenceDate.isFinite,
                  anchor.nativeTimestamp?.isFinite != false,
                  anchor.nativeClock?.isValid != false,
                  let pending = anchor.pendingBatch,
                  (1...Int(Int32.max)).contains(pending.sampleCount),
                  pending.upperBound.timeIntervalSinceReferenceDate.isFinite,
                  pending.nativeUpperBoundBits.map({ Double(bitPattern: $0).isFinite }) != false,
                  pending.upperBound >= anchor.timestamp else { throw .invalidToken }
            switch pending.mode {
            case .sampleCount:
                guard pending.lowerBound == nil else { throw .invalidToken }
            case .timeRange:
                guard let lower = pending.lowerBound, lower.timeIntervalSinceReferenceDate.isFinite,
                      lower >= anchor.timestamp, lower < pending.upperBound else { throw .invalidToken }
            }
        }
    }

    /// Replay refuses changed source bindings, unavailable history and malformed tokens.
    public enum BatchReplayError: Error, Equatable, Sendable {
        /// The token is malformed, of an unknown version, or larger than 16 KiB.
        case invalidToken
        /// The token was fetched from a different sensor than the one passed to the replay.
        case sourceMismatch
        /// No device of the token's product type is available.
        case deviceUnavailable
        /// SensorKit no longer returns the same batch, for example because its history expired or changed.
        case batchUnavailable
    }
}

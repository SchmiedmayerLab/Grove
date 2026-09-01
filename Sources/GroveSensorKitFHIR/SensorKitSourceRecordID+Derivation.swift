//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

import CryptoKit
import Foundation
public import GroveSensorKit


@available(iOS 18, *)
extension SensorKitSourceRecordID {
    /// Derives the identity of one record at a durable SensorKit acquisition coordinate.
    ///
    /// SensorKit publishes no durable record identifier. Its anchored fetcher instead allocates an
    /// `AcquisitionBatchCoordinate` before exposing a batch. Combining that coordinate
    /// with the cursor's sensor and device partitions plus the record's ordinal preserves
    /// multiplicity: byte-identical records delivered at different coordinates remain distinct,
    /// while an exact retry reproduces the same identifier.
    ///
    /// Persist a digest of the source fields and native bytes beside this identifier. Before reusing
    /// the identifier on a retry, compare the new digest with the persisted digest and fail the batch
    /// if they differ. Content is deliberately not part of this derivation: changing content at the
    /// same coordinate is a retry-integrity failure, not a new record.
    ///
    /// - Parameters:
    ///   - acquisitionBatch: The persisted coordinate supplied by `AnchoredBatch.info`.
    ///   - sourceToken: The stream's closed SensorKit catalog token.
    ///   - deviceProductType: The device partition supplied by `AnchoredBatch.info.device`.
    ///   - recordOrdinal: The zero-based position of the record in `AnchoredBatch.samples`.
    public static func derived(
        acquisitionBatch: SensorKit.AcquisitionBatchCoordinate,
        sourceToken: String,
        deviceProductType: String,
        recordOrdinal: UInt64
    ) -> SensorKitSourceRecordID {
        var framed = Data()
        for component in [
            "org.grovealliance.sensorkit.source-record.v0",
            sourceToken,
            deviceProductType,
            acquisitionBatch.stableValue,
            String(recordOrdinal)
        ] {
            let bytes = Data(component.utf8)
            var byteCount = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &byteCount) { framed.append(contentsOf: $0) }
            framed.append(bytes)
        }
        return SensorKitSourceRecordID(version8UUID(from: Data(SHA256.hash(data: framed))))
    }

    /// An RFC 9562 version-8 UUID carrying the leading bits of the framed SHA-256 digest.
    private static func version8UUID(from digest: Data) -> UUID {
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

#endif

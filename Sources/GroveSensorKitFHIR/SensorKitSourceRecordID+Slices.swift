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
    public enum SliceIdentityError: Error, Equatable, Sendable { case invalidRange }

    /// Identifies immutable row coverage within a retained acquisition batch, independently of study policy.
    /// This namespace is separate from whole-record identities. Exact replay needs the original ordered source digest.
    /// The guarantee depends on retained source state; it does not extend to independent first fetches or reinstalls.
    public static func derivedSlice(
        acquisitionBatch: SensorKit.AcquisitionBatchCoordinate,
        sourceToken: String,
        deviceProductType: String,
        rows: Range<UInt64>
    ) throws -> SensorKitSourceRecordID {
        guard !rows.isEmpty else { throw SliceIdentityError.invalidRange }
        var framed = Data()
        for component in [
            "org.grovealliance.sensorkit.source-slice.v0",
            sourceToken, deviceProductType, acquisitionBatch.stableValue,
            String(rows.lowerBound), String(rows.upperBound)
        ] {
            let bytes = Data(component.utf8)
            var byteCount = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &byteCount) { framed.append(contentsOf: $0) }
            framed.append(bytes)
        }
        return SensorKitSourceRecordID(version8UUID(from: Data(SHA256.hash(data: framed))))
    }
}
#endif

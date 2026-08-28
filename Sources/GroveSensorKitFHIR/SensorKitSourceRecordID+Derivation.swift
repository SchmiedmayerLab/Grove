//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKitSourceRecordID {
    /// Derives a record identity from the exact bytes a recording carries.
    ///
    /// SensorKit publishes no durable sample identifier, and the contract permits reusing an id only
    /// while every source field and byte is unchanged. Grove therefore derives it rather than leaving
    /// each producer to invent a hash: identical bytes from the same stream and device converge on one
    /// record across retries, and any change produces a new one. Two producers that derive it this way
    /// agree; two that each invented a scheme do not.
    ///
    /// - Parameters:
    ///   - payload: The exact recording bytes.
    ///   - sourceToken: The stream's catalog token, so the same bytes from two streams stay distinct.
    ///   - deviceDescriptor: A stable description of the recording device.
    public static func derived(
        fromPayload payload: Data,
        sourceToken: String,
        deviceDescriptor: String
    ) -> SensorKitSourceRecordID {
        var hasher = SHA256()
        // The prefix is length-delimited so that a token ending in the separator cannot collide with
        // a device descriptor beginning with it.
        hasher.update(data: Data("grove-sensorkit-record-id-v1".utf8))
        for part in [sourceToken, deviceDescriptor] {
            let utf8 = Data(part.utf8)
            withUnsafeBytes(of: UInt64(utf8.count).bigEndian) { hasher.update(bufferPointer: $0) }
            hasher.update(data: utf8)
        }
        hasher.update(data: payload)
        return SensorKitSourceRecordID(uuid(from: Data(hasher.finalize())))
    }

    /// A UUID carrying the digest's leading bits, stamped version 4 and RFC 4122 variant.
    private static func uuid(from digest: Data) -> UUID {
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

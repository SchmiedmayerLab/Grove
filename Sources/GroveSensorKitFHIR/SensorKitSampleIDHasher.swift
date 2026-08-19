//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
public import Foundation


/// The secret that scopes SensorKit sample identifiers to one deployment.
///
/// The identifier is a keyed digest rather than a plain hash, because a plain hash of a
/// sample's content is a global name for that content: the same participant extracted
/// into two independently de-identified datasets carries the same identifier in both, so
/// the datasets join on it alone. The preimages are small enough to search, too — a wear
/// state is a sensor name, a timestamp, a boolean and two two-valued enums, so an
/// attacker holding a date-shifted copy can recover the true timestamps by trying shifts.
///
/// A key that never leaves the deployment removes both, and costs nothing that matters:
/// deduplication only ever compares identifiers within one deployment, which is exactly
/// what `ifNoneExist` needs.
///
/// Draw at least 32 bytes from a CSPRNG once per deployment, keep them wherever the
/// deployment keeps its other secrets, and never ship them alongside the data. Rotating
/// the key changes every identifier derived from it, so a rotation means re-uploading.
public struct SensorKitIdentifierKey: Sendable {
    /// Why key material was rejected.
    public enum KeyError: Error, CustomStringConvertible {
        /// The key material fell short of the 32 bytes the scheme requires.
        case insufficientKeyMaterial(byteCount: Int)

        public var description: String {
            switch self {
            case let .insufficientKeyMaterial(byteCount):
                """
                A SensorKit identifier key needs at least \(SensorKitIdentifierKey.minimumByteCount) bytes \
                of key material, not \(byteCount)
                """
            }
        }
    }

    /// A shorter key would leave the identifiers searchable by the very attacker the
    /// keying exists to stop.
    static let minimumByteCount = 32

    fileprivate let symmetricKey: SymmetricKey

    /// Creates a key from raw key material — at least 32 bytes drawn from a CSPRNG.
    ///
    /// - throws: ``KeyError/insufficientKeyMaterial(byteCount:)`` for anything shorter.
    public init(keyMaterial: some ContiguousBytes) throws {
        let byteCount = keyMaterial.withUnsafeBytes(\.count)
        guard byteCount >= Self.minimumByteCount else {
            throw KeyError.insufficientKeyMaterial(byteCount: byteCount)
        }
        symmetricKey = SymmetricKey(data: keyMaterial)
    }

    /// Creates a key by stretching a deployment secret, e.g. a passphrase read from the
    /// keychain, through HKDF.
    ///
    /// Stretching fixes the key's length, not its entropy: a guessable passphrase stays
    /// guessable. Prefer ``init(keyMaterial:)`` with CSPRNG bytes wherever the deployment
    /// can store them.
    public init(secret: String) {
        symmetricKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(secret.utf8)),
            info: Data("grove-sensorkit-identifier-key".utf8),
            outputByteCount: Self.minimumByteCount
        )
    }
}


/// Derives a deterministic identifier from a sample's own content.
///
/// SensorKit assigns no record identity, so re-fetching a window would otherwise produce
/// fresh identifiers and duplicate uploads. A keyed digest over the content makes the
/// identifier reproducible: within a deployment the same sample always yields the same
/// value, and consumers deduplicate on `(system, value)` exactly as for HealthKit
/// records. Across deployments the values are unrelated — see ``SensorKitIdentifierKey``.
public struct SensorKitSampleIDHasher: Sendable {
    /// A byte that cannot occur in UTF-8, so an absent value is distinguishable from
    /// every present one.
    private static let absentMarker = Data([0xFF])

    private var hasher: HMAC<SHA256>

    public init(key: SensorKitIdentifierKey) {
        hasher = HMAC<SHA256>(key: key.symmetricKey)
    }

    public mutating func combine(_ value: some BinaryInteger) {
        combine(String(describing: value))
    }

    public mutating func combine(_ value: Double) {
        // The bit pattern, so the digest cannot shift with formatting or locale.
        combine(String(value.bitPattern))
    }

    public mutating func combine(_ value: Date) {
        combine(value.timeIntervalSince1970)
    }

    public mutating func combine(_ value: Date?) {
        if let value {
            combine(value)
        } else {
            update(Self.absentMarker)
        }
    }

    public mutating func combine(_ value: UUID) {
        combine(value.uuidString)
    }

    public mutating func combine(_ value: String) {
        update(Data(value.utf8))
    }

    public mutating func combine(_ value: String?) {
        if let value {
            combine(value)
        } else {
            update(Self.absentMarker)
        }
    }

    /// Finalizes the digest as a UUID (the first 16 bytes, RFC 4122 v4-shaped).
    public func finalize() -> UUID {
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private mutating func update(_ data: Data) {
        hasher.update(data: data)
        // A separator, so ("ab", "c") and ("a", "bc") cannot collide.
        hasher.update(data: Data([0x00]))
    }
}

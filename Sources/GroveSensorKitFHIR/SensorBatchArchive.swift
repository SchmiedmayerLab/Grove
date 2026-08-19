//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Compression
public import Foundation
import GroveFoundation


/// Packages FHIR resources and their sidecar payload files into one archive for upload.
///
/// The container is a POSIX ustar tar stream, optionally compressed — a format every
/// platform and analysis stack reads natively. File paths inside the archive match the
/// relative URLs the FHIR resources use (`DocumentReference.content.attachment.url`), so
/// a consumer that unpacks the archive can resolve every reference locally. Paths are
/// therefore load-bearing: one longer than a ustar header can carry, or claimed twice,
/// is rejected rather than silently truncated or shadowed.
///
/// Archives are deterministic — the same entries in the same order always produce the
/// same bytes, on every platform — so an upload can be hashed and compared.
public struct SensorBatchArchive: Sendable {
    /// How the archive stream is compressed.
    public enum Compression: Sendable {
        /// The raw tar stream.
        case none
        /// gzip (RFC 1952) — universally readable, built into the platform.
        case gzip
        /// zstd — smaller and faster than gzip; Grove vendors the library, so it needs
        /// nothing from the app.
        case zstd
        /// An app-supplied codec; receives the tar stream, returns the compressed bytes.
        /// The suggested filename extension names the codec.
        case custom(fileExtension: String, @Sendable (Data) throws -> Data)

        var fileExtension: String {
            switch self {
            case .none:
                "tar"
            case .gzip:
                "tar.gz"
            case .zstd:
                "tar.zst"
            case .custom(let fileExtension, _):
                "tar.\(fileExtension)"
            }
        }
    }

    /// An error occurring while assembling a sensor batch archive.
    public enum ArchiveError: Error {
        /// The path is longer than the 100 bytes a ustar header carries. Shorten it —
        /// truncating would break the parity with the FHIR references.
        case pathTooLong(String)
        /// Two files claim the same archive path, so one would shadow the other.
        case duplicatePath(String)
        case compressionFailed
    }

    /// The longest path a ustar header field carries.
    private static let maximumPathLength = 100

    private var entries: [Tar.Entry] = []

    /// The paths currently in the archive, in insertion order.
    public var paths: [String] {
        entries.map(\.path)
    }

    public init() {}

    /// Adds a file to the archive.
    ///
    /// - parameter path: The file's path inside the archive; must match the relative
    ///     URL any FHIR resource uses to reference it, and fit in 100 UTF-8 bytes.
    /// - parameter data: The file contents.
    public mutating func addFile(path: String, data: Data) throws {
        guard path.utf8.count <= Self.maximumPathLength else {
            throw ArchiveError.pathTooLong(path)
        }
        guard !entries.contains(where: { $0.path == path }) else {
            throw ArchiveError.duplicatePath(path)
        }
        entries.append(.file(path, contents: data))
    }

    /// Serializes the archive.
    public func data(compression: Compression = .gzip) throws -> Data {
        let tar = try Tar.archive(entries)
        switch compression {
        case .none:
            return tar
        case .gzip:
            return try Self.gzip(tar)
        case .zstd:
            return try Zstd.compress(tar)
        case .custom(_, let compress):
            return try compress(tar)
        }
    }
}


// MARK: gzip (RFC 1952)

extension SensorBatchArchive {
    private static func gzip(_ input: Data) throws -> Data {
        // A zeroed MTIME field, so the same entries always produce the same bytes.
        var output = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        output.append(try deflate(input))
        var crc = crc32(input).littleEndian
        withUnsafeBytes(of: &crc) { output.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: input.count).littleEndian
        withUnsafeBytes(of: &size) { output.append(contentsOf: $0) }
        return output
    }

    private static func deflate(_ input: Data) throws -> Data {
        // COMPRESSION_ZLIB produces a raw deflate stream, which is exactly what the
        // gzip container wraps.
        let capacity = input.count + input.count / 2 + 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer {
            destination.deallocate()
        }
        let written = input.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else {
                return 0
            }
            return compression_encode_buffer(destination, capacity, base, input.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else {
            throw ArchiveError.compressionFailed
        }
        return Data(bytes: destination, count: written)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (0xEDB88320 & (0 &- (crc & 1)))
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

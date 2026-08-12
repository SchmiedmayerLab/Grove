//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SpeziFoundation


/// A minimal, deterministic tar (ustar) implementation for study bundle archives.
///
/// Writing sorts entries and zeroes all timestamps and ownership, so archiving the same bundle
/// contents always produces the same bytes, on every platform.
enum StudyBundleTar {
    enum TarError: Error {
        /// The archive contains an entry whose path would escape the extraction directory.
        case unsafeEntryPath(String)
        /// The archive is truncated or a header field cannot be parsed.
        case malformedArchive
        /// An entry path exceeds the 100 characters a ustar header can carry.
        case entryPathTooLong(String)
    }

    private static let blockSize = 512
    private static let nameFieldLength = 100

    static func archive(directoryAt root: URL) throws -> Data {
        let fileManager = FileManager.default
        let rootPath = root.resolvingSymlinksInPath().path(percentEncoded: false)
        var entryPaths: [String] = []
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                let urlPath = url.resolvingSymlinksInPath().path(percentEncoded: false)
                var path = urlPath.trimmingPrefix(rootPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if fileManager.isDirectory(at: url) {
                    path += "/"
                }
                guard path.utf8.count <= nameFieldLength else {
                    throw TarError.entryPathTooLong(String(path))
                }
                entryPaths.append(String(path))
            }
        }
        var data = Data()
        for path in entryPaths.sorted() {
            let contents = path.hasSuffix("/") ? Data() : try Data(contentsOf: root.appending(path: path))
            data.append(header(path: path, size: contents.count))
            data.append(contents)
            data.append(padding(after: contents.count))
        }
        data.append(Data(count: blockSize * 2))
        return data
    }

    static func extract(_ data: Data, to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        // Resolve the root once and derive every target from it, so the containment check cannot
        // be skewed by symlinks resolving differently for existing and not-yet-existing paths.
        let root = root.resolvingSymlinksInPath()
        let rootPath = root.path(percentEncoded: false)
        var offset = data.startIndex
        while offset + blockSize <= data.endIndex {
            let header = data[offset..<offset + blockSize]
            offset += blockSize
            guard header.contains(where: { $0 != 0 }) else {
                // The end-of-archive marker is two consecutive zero blocks.
                guard offset + blockSize <= data.endIndex,
                      !data[offset..<offset + blockSize].contains(where: { $0 != 0 }) else {
                    throw TarError.malformedArchive
                }
                return
            }
            let name = string(in: header, at: 0, length: nameFieldLength)
            guard let size = octal(in: header, at: 124, length: 12), size >= 0 else {
                throw TarError.malformedArchive
            }
            let typeflag = header[header.startIndex + 156]
            let paddedSize = size + padding(after: size).count
            guard offset + paddedSize <= data.endIndex else {
                throw TarError.malformedArchive
            }
            let contents = data[offset..<offset + size]
            offset += paddedSize
            let target = root.appending(path: name).standardized
            let targetPath = target.path(percentEncoded: false)
            guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
                throw TarError.unsafeEntryPath(name)
            }
            switch typeflag {
            case UInt8(ascii: "5"):
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            case UInt8(ascii: "0"), 0:
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents).write(to: target)
            default:
                continue // entry kinds this implementation never writes (links, pax metadata, ...)
            }
        }
        throw TarError.malformedArchive // the blocks ran out before the end-of-archive marker
    }

    private static func header(path: String, size: Int) -> Data {
        var header = Data(count: blockSize)
        header.replace(at: 0, with: path, length: nameFieldLength)
        header.replace(at: 100, with: path.hasSuffix("/") ? "0000755 " : "0000644 ", length: 8) // mode
        header.replace(at: 108, with: "0000000 ", length: 8) // uid
        header.replace(at: 116, with: "0000000 ", length: 8) // gid
        header.replace(at: 124, with: String(format: "%011o ", size), length: 12)
        header.replace(at: 136, with: "00000000000 ", length: 12) // mtime
        header.replace(at: 148, with: "        ", length: 8) // checksum placeholder
        header.replace(at: 156, with: path.hasSuffix("/") ? "5" : "0", length: 1)
        header.replace(at: 257, with: "ustar", length: 6)
        header.replace(at: 263, with: "00", length: 2)
        header.replace(at: 329, with: "0000000 ", length: 8) // devmajor
        header.replace(at: 337, with: "0000000 ", length: 8) // devminor
        let checksum = header.reduce(0) { $0 + Int($1) }
        header.replace(at: 148, with: String(format: "%06o", checksum) + "\0 ", length: 8)
        return header
    }

    private static func padding(after size: Int) -> Data {
        let remainder = size % blockSize
        return Data(count: remainder == 0 ? 0 : blockSize - remainder)
    }

    private static func string(in header: Data, at offset: Int, length: Int) -> String {
        let field = header[(header.startIndex + offset)..<(header.startIndex + offset + length)]
        return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func octal(in header: Data, at offset: Int, length: Int) -> Int? {
        Int(string(in: header, at: offset, length: length).trimmingCharacters(in: .whitespaces), radix: 8)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// The file extension of a compressed study bundle archive.
    public static let archiveFileExtension = "\(fileExtension).tar.zst"

    /// Extracts the zstd-compressed tar archive at `archiveUrl` into `bundleUrl`, replacing any
    /// previous contents, and opens the bundle.
    public static func unarchive(_ archiveUrl: URL, to bundleUrl: URL) throws -> StudyBundle {
        // Far beyond any real study bundle, but a bound on what a hostile archive can allocate.
        let maximumDecompressedSize = 1 << 30
        let tar = try Zstd.decompress(Data(contentsOf: archiveUrl), maximumDecompressedSize: maximumDecompressedSize)
        let fileManager = FileManager.default
        // Extract into a staging sibling first, so a malformed archive cannot destroy a
        // previously extracted bundle.
        let stagingUrl = bundleUrl.deletingLastPathComponent()
            .appending(path: "\(bundleUrl.lastPathComponent).staging-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: stagingUrl)
        }
        try StudyBundleTar.extract(tar, to: stagingUrl)
        if fileManager.itemExists(at: bundleUrl) {
            try fileManager.removeItem(at: bundleUrl)
        }
        try fileManager.moveItem(at: stagingUrl, to: bundleUrl)
        return try StudyBundle(bundleUrl: bundleUrl)
    }

    /// Archives the bundle into a zstd-compressed tar file at `archiveUrl`.
    ///
    /// The archive is deterministic: identical bundle contents produce identical archives,
    /// on every platform.
    public func archive(to archiveUrl: URL, compressionLevel: Zstd.CompressionOptions.Level = .default) throws {
        let tar = try StudyBundleTar.archive(directoryAt: bundleUrl)
        let compressed = try Zstd.compress(tar, options: .init(level: compressionLevel))
        try compressed.write(to: archiveUrl)
    }
}


extension Data {
    fileprivate mutating func replace(at offset: Int, with value: String, length: Int) {
        let bytes = Array(value.utf8.prefix(length))
        replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }
}

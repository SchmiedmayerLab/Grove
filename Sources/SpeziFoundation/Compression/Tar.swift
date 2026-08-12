//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


/// A deterministic reader and writer for the tar (ustar) container format.
///
/// `Tar` bundles multiple files into a single stream and reads them back. It is the container
/// layer beneath a stream compressor such as ``Zstd``, which compresses one stream but does not
/// itself group files.
///
/// The implementation covers the subset needed to package a directory of files: regular files and
/// directories whose paths fit the 100-character ustar name field. Writing is deterministic —
/// entries are emitted in a caller-defined order with zeroed timestamps and ownership — so the
/// same entries always produce the same bytes, on every platform. Reading validates each header's
/// checksum and the archive's end-of-archive marker.
package enum Tar {
    /// A single member of a tar archive.
    package struct Entry: Hashable, Sendable {
        /// Whether an entry is a file or a directory.
        package enum Kind: Hashable, Sendable {
            case file
            case directory
        }

        /// The entry's path within the archive, relative to its root.
        package var path: String
        /// Whether the entry is a file or a directory.
        package var kind: Kind
        /// The file contents; empty for directories.
        package var contents: Data

        /// Creates a file entry.
        package static func file(_ path: String, contents: Data) -> Entry {
            Entry(path: path, kind: .file, contents: contents)
        }

        /// Creates a directory entry.
        package static func directory(_ path: String) -> Entry {
            Entry(path: path.hasSuffix("/") ? path : path + "/", kind: .directory, contents: Data())
        }
    }

    package enum TarError: Error {
        /// An entry path exceeds the 100 characters a ustar header can carry.
        case pathTooLong(String)
        /// A header could not be parsed, or its stored checksum did not match its contents.
        case malformedHeader
        /// The archive ended before an entry's declared contents.
        case truncated
        /// The archive is missing its two-zero-block end-of-archive marker.
        case missingEndMarker
    }

    /// Packs the entries into a tar archive.
    ///
    /// - Note: entries are emitted in the order given; sort them beforehand for a deterministic archive.
    package static func archive(_ entries: [Entry]) throws -> Data {
        var data = Data()
        for entry in entries {
            let header = try Header(entry)
            data.append(header.makeBlock().encoded())
            data.append(entry.contents)
            data.append(Block.padding(forContentOfLength: entry.contents.count))
        }
        data.append(Data(count: Block.size * Block.endMarkerBlockCount))
        return data
    }

    /// Reads the entries from a tar archive, validating each header and the end-of-archive marker.
    package static func entries(in data: Data) throws -> [Entry] {
        var entries: [Entry] = []
        var blocks = BlockReader(data)
        while let block = blocks.next() {
            guard !block.isZero else {
                // The end-of-archive marker is two consecutive zero blocks.
                guard let following = blocks.next(), following.isZero else {
                    throw TarError.missingEndMarker
                }
                return entries
            }
            let header = try Header(decoding: block)
            let contents = try blocks.read(byteCount: header.size)
            if header.kind == .directory {
                entries.append(.directory(header.path))
            } else {
                entries.append(.file(header.path, contents: contents))
            }
        }
        throw TarError.missingEndMarker
    }
}


extension Tar {
    /// A typed view of a 512-byte ustar header block.
    ///
    /// The `POSIX` ustar layout places each field at a fixed offset; ``Field`` names those offsets
    /// so the byte layout is declared once rather than spread through the encode and decode paths.
    fileprivate struct Header {
        /// A fixed-width region of a header block.
        struct Field {
            static let name = Field(offset: 0, length: 100)
            static let mode = Field(offset: 100, length: 8)
            static let ownerID = Field(offset: 108, length: 8)
            static let groupID = Field(offset: 116, length: 8)
            static let size = Field(offset: 124, length: 12)
            static let modificationTime = Field(offset: 136, length: 12)
            static let checksum = Field(offset: 148, length: 8)
            static let typeFlag = Field(offset: 156, length: 1)
            static let magic = Field(offset: 257, length: 6)
            static let version = Field(offset: 263, length: 2)
            static let deviceMajor = Field(offset: 329, length: 8)
            static let deviceMinor = Field(offset: 337, length: 8)

            let offset: Int
            let length: Int
        }

        static let fileTypeFlag: Character = "0"
        static let directoryTypeFlag: Character = "5"

        var path: String
        var size: Int
        var kind: Tar.Entry.Kind

        init(_ entry: Tar.Entry) throws {
            guard entry.path.utf8.count <= Field.name.length else {
                throw TarError.pathTooLong(entry.path)
            }
            self.path = entry.path
            self.size = entry.contents.count
            self.kind = entry.kind
        }

        init(decoding block: Block) throws {
            guard block.string(.magic) == "ustar", let size = block.octal(.size) else {
                throw TarError.malformedHeader
            }
            guard block.storedChecksum == block.computedChecksum else {
                throw TarError.malformedHeader
            }
            self.path = block.string(.name)
            self.size = size
            self.kind = block.string(.typeFlag) == String(Self.directoryTypeFlag) ? .directory : .file
        }

        func makeBlock() -> Block {
            let typeFlag = kind == .directory ? Self.directoryTypeFlag : Self.fileTypeFlag
            var block = Block()
            block.setString(path, at: .name)
            block.setOctal(kind == .directory ? 0o755 : 0o644, at: .mode)
            block.setOctal(0, at: .ownerID)
            block.setOctal(0, at: .groupID)
            block.setOctal(size, at: .size)
            block.setOctal(0, at: .modificationTime)
            block.setString(String(typeFlag), at: .typeFlag)
            block.setString("ustar", at: .magic)
            block.setString("00", at: .version)
            block.setOctal(0, at: .deviceMajor)
            block.setOctal(0, at: .deviceMinor)
            block.applyChecksum()
            return block
        }
    }
}


extension Tar {
    /// A single 512-byte tar block with typed field access.
    fileprivate struct Block {
        static let size = 512
        static let endMarkerBlockCount = 2

        private var bytes: [UInt8]

        var isZero: Bool {
            bytes.allSatisfy { $0 == 0 }
        }

        /// The checksum stored in the header, or `nil` when the field is not a valid octal number.
        var storedChecksum: Int? {
            octal(.checksum)
        }

        /// The checksum of the block, computed with the checksum field taken to be spaces.
        var computedChecksum: Int {
            var sum = 0
            for index in bytes.indices {
                let field = Header.Field.checksum
                let withinChecksumField = index >= field.offset && index < field.offset + field.length
                sum += withinChecksumField ? Int(UInt8(ascii: " ")) : Int(bytes[index])
            }
            return sum
        }

        init() {
            bytes = [UInt8](repeating: 0, count: Self.size)
        }

        init?(_ slice: Data) {
            guard slice.count == Self.size else {
                return nil
            }
            bytes = Array(slice)
        }

        /// The number of zero bytes that pad `length` content bytes up to a whole number of blocks.
        static func padding(forContentOfLength length: Int) -> Data {
            let remainder = length % size
            return Data(count: remainder == 0 ? 0 : size - remainder)
        }

        /// The NUL-terminated ASCII string stored in `field`. Spaces are preserved: they are legal
        /// in a name field, and the numeric fields strip their own padding in ``octal(_:)``.
        func string(_ field: Header.Field) -> String {
            let region = bytes[field.offset..<field.offset + field.length]
            return String(decoding: region.prefix { $0 != 0 }, as: UTF8.self)
        }

        /// The octal number stored in `field`, or `nil` when it is not a non-negative octal number.
        func octal(_ field: Header.Field) -> Int? {
            let text = string(field).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, let value = Int(text, radix: 8), value >= 0 else {
                return nil
            }
            return value
        }

        mutating func setString(_ value: String, at field: Header.Field) {
            let encoded = Array(value.utf8.prefix(field.length))
            bytes.replaceSubrange(field.offset..<field.offset + encoded.count, with: encoded)
        }

        /// Writes `value` as a right-justified, zero-padded octal number followed by a space,
        /// the encoding ustar uses for its numeric fields.
        mutating func setOctal(_ value: Int, at field: Header.Field) {
            let digits = String(value, radix: 8)
            let padded = String(repeating: "0", count: max(0, field.length - 1 - digits.count)) + digits
            setString(padded + " ", at: field)
        }

        /// Stamps the block's own checksum into its checksum field.
        mutating func applyChecksum() {
            let field = Header.Field.checksum
            // A six-digit octal number, then NUL and a space, is the conventional checksum encoding.
            let digits = String(computedChecksum, radix: 8)
            let padded = String(repeating: "0", count: max(0, 6 - digits.count)) + digits
            let encoded = Array((padded + "\0 ").utf8.prefix(field.length))
            bytes.replaceSubrange(field.offset..<field.offset + encoded.count, with: encoded)
        }

        func encoded() -> Data {
            Data(bytes)
        }
    }
}


extension Tar {
    /// Walks a `Data` buffer one 512-byte block at a time, tracking the read position.
    fileprivate struct BlockReader {
        private let data: Data
        private var offset: Int

        init(_ data: Data) {
            self.data = data
            self.offset = data.startIndex
        }

        mutating func next() -> Block? {
            guard offset + Block.size <= data.endIndex else {
                return nil
            }
            defer { offset += Block.size }
            return Block(data[offset..<offset + Block.size])
        }

        /// Reads `byteCount` content bytes and advances past their block padding.
        mutating func read(byteCount: Int) throws -> Data {
            let paddedCount = byteCount + Block.padding(forContentOfLength: byteCount).count
            guard offset + paddedCount <= data.endIndex else {
                throw TarError.truncated
            }
            defer { offset += paddedCount }
            return Data(data[offset..<offset + byteCount])
        }
    }
}

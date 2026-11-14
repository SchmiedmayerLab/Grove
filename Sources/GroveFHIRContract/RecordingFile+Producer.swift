//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


extension RecordingFile {
    /// Synchronously stages a package-owned encoder with a bounded write buffer. A thrown encoder,
    /// capacity or cancellation error closes the private file without exposing a successful prefix.
    package static func stage(
        maximumByteCount: Int,
        producing body: (_ append: (Data) throws -> Void) throws -> Void
    ) throws -> Self {
        guard (1...Int(Int32.max)).contains(maximumByteCount) else { throw FileError.invalidByteLimit }
        try Task.checkCancellation()
        let storage = try RecordingStaging.create()
        var pending = Data()
        var count = 0
        var hasher = AttachmentHasher()
        var failure: (any Error)?
        func flush() throws {
            guard !pending.isEmpty else {
                return
            }
            try write(pending, to: storage.descriptor, offset: count)
            hasher.update(pending)
            count += pending.count
            pending.removeAll(keepingCapacity: true)
        }
        try body { bytes in
            if let failure { throw failure }
            do {
                try Task.checkCancellation()
                guard bytes.count <= maximumByteCount - count - pending.count else { throw FileError.byteLimitExceeded }
                var remaining = bytes[...]
                while !remaining.isEmpty {
                    let prefix = remaining.prefix(chunkByteCount - pending.count)
                    pending.append(prefix)
                    remaining = remaining.dropFirst(prefix.count)
                    if pending.count == chunkByteCount { try flush() }
                }
            } catch {
                failure = error
                throw error
            }
        }
        if let failure { throw failure }
        try Task.checkCancellation()
        try flush()
        guard count > 0 else { throw FileError.emptySource }
        return Self(byteCount: count, attachmentSHA1: hasher.finalize(), storage: storage)
    }
}

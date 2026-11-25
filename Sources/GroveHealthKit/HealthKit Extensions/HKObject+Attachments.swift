//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CryptoKit
public import Foundation
public import HealthKit


/// Starts streaming one attachment's bytes into `handler`, as `HKAttachmentStore.streamData(for:dataHandler:)` does, and
/// returns the progress that cancels the stream.
package typealias AttachmentByteStream = (
    _ handler: @escaping @Sendable (_ chunk: Data?, _ error: (any Error)?, _ done: Bool) -> Void
) -> Progress


/// Ends one stream exactly once: with its last chunk, its first error, or the task's cancellation, whichever comes first,
/// whatever the data handler reports afterwards. Cancellation also cancels the stream's progress, so HealthKit stops, for
/// example, waiting on an iCloud download.
@available(iOS 18, macOS 15, watchOS 11, *)
private final class StreamControl: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var progress: Progress?
    private var cancelled = false

    /// Holds `continuation` until the stream ends, and returns whether to start it: a task cancelled before the stream
    /// started resumes it with `CancellationError` at once.
    func hold(_ continuation: CheckedContinuation<Void, any Error>) -> Bool {
        let cancelled = lock.withLock {
            if !self.cancelled {
                self.continuation = continuation
            }
            return self.cancelled
        }
        if cancelled {
            continuation.resume(throwing: CancellationError())
        }
        return !cancelled
    }

    /// Notes the started stream's `progress`, which is cancelled at once if the task was cancelled while it started.
    func started(_ progress: Progress) {
        let cancelled = lock.withLock {
            self.progress = progress
            return self.cancelled
        }
        if cancelled {
            progress.cancel()
        }
    }

    /// Cancels the stream and ends it with `CancellationError`.
    func cancel() {
        let (progress, continuation) = lock.withLock {
            cancelled = true
            defer {
                self.continuation = nil
            }
            return (self.progress, self.continuation)
        }
        progress?.cancel()
        continuation?.resume(throwing: CancellationError())
    }

    /// Ends the stream with `error`, or successfully without one.
    func end(throwing error: (any Error)? = nil) {
        let continuation = lock.withLock {
            defer {
                self.continuation = nil
            }
            return self.continuation
        }
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }
}


/// Writes one attachment's bytes to a file as they arrive, counting them and computing their SHA-1 and SHA-256 digests on
/// the way, so no more than one chunk is ever held.
///
/// HealthKit calls a data handler from a queue of its own, so every mutation happens under the lock.
@available(iOS 18, macOS 15, watchOS 11, *)
package final class AttachmentFileWriter: @unchecked Sendable {
    /// What the writer wrote: the byte count and the two digests.
    package struct Written: Hashable, Sendable {
        package let byteCount: Int
        package let sha1: Data
        package let sha256: Data
    }

    private let lock = NSLock()
    private let handle: FileHandle
    private var sha1 = Insecure.SHA1()
    private var sha256 = SHA256()
    private var byteCount = 0
    private var closed = false

    /// A writer into a new, empty file at `url`, replacing any file there.
    ///
    /// Anything else at `url`, such as a directory, makes it throw and stay untouched. A file it created but couldn't open
    /// is removed again.
    package init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Writes the bytes `start` streams into a new file at `url`, and returns what it wrote.
    ///
    /// Any failure, of the stream or of finishing the file, and the task's cancellation throw and remove the file. Only a
    /// file this call created is ever removed: if the writer can't be created, whatever is at `url` stays.
    package static func copy(to url: URL, using start: AttachmentByteStream) async throws -> Written {
        let writer = try AttachmentFileWriter(url: url)
        do {
            try await writer.stream(using: start)
            return try writer.finish()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Appends `chunk` to the file and to the count and digests.
    package func append(_ chunk: Data) throws {
        try lock.withLock {
            precondition(!closed, "An attachment's bytes were appended after its file was finished")
            try handle.write(contentsOf: chunk)
            sha1.update(data: chunk)
            sha256.update(data: chunk)
            byteCount += chunk.count
        }
    }

    /// Closes the file and returns what was written.
    package func finish() throws -> Written {
        try lock.withLock {
            precondition(!closed, "An attachment's file was finished twice")
            closed = true
            try handle.synchronize()
            try handle.close()
            return Written(byteCount: byteCount, sha1: Data(sha1.finalize()), sha256: Data(sha256.finalize()))
        }
    }

    /// Streams the bytes `start` delivers into the file, returning once the last chunk arrived.
    ///
    /// Cancelling the task cancels the stream's progress and throws `CancellationError` at once.
    package func stream(using start: AttachmentByteStream) async throws {
        let control = StreamControl()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard control.hold(continuation) else {
                    return
                }
                control.started(start { [self] chunk, error, done in
                    if let error {
                        control.end(throwing: error)
                        return
                    }
                    if let chunk {
                        do {
                            try append(chunk)
                        } catch {
                            control.end(throwing: error)
                            return
                        }
                    }
                    if done {
                        control.end()
                    }
                })
            }
        } onCancel: {
            control.cancel()
        }
    }

    deinit {
        try? handle.close()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKAttachment {
    /// A copy of an attachment's exact bytes in a file, with their count and digests.
    public struct FileCopy: Sendable {
        /// The attachment HealthKit stores, with its identifier, name, content type, creation date and metadata.
        public let attachment: HKAttachment
        /// The file holding the attachment's bytes.
        public let url: URL
        /// The number of the attachment's bytes.
        public let byteCount: Int
        /// The SHA-1 digest of the attachment's bytes, which FHIR R4's `Attachment.hash` states.
        public let sha1: Data
        /// The SHA-256 digest of the attachment's bytes, such as for naming them by their content.
        public let sha256: Data
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKObject {
    /// Copies every file HealthKit stores with this object, such as a clinical record's PDF, into `directory`, one file per
    /// attachment, named by the attachment's identifier.
    ///
    /// Each attachment's bytes stream into its file chunk by chunk, and their count and digests are computed as they pass,
    /// so memory stays flat whatever the file's size. HealthKit may need to download an attachment from iCloud first.
    ///
    /// Any failure throws and removes every file the call wrote, so a caller never sees part of an object's attachments: an
    /// exporter that cannot read them fails the object's batch and tries again later rather than exporting the object
    /// without them. Cancelling the task cancels the attachment HealthKit is streaming, or waiting to download, and throws
    /// `CancellationError` in the same way.
    ///
    /// - Parameters:
    ///   - healthStore: The store that holds the object.
    ///   - directory: An existing directory the caller owns; a file of the same name in it is replaced.
    /// - Returns: One copy per attachment, in the order HealthKit lists them; none for an object without attachments.
    public func copyAttachments(from healthStore: HKHealthStore, into directory: URL) async throws -> [HKAttachment.FileCopy] {
        let store = HKAttachmentStore(healthStore: healthStore)
        let attachments = try await store.attachments(for: self)
        var copies: [HKAttachment.FileCopy] = []
        do {
            for attachment in attachments {
                // A cancelled task, such as an expiring background task, copies no further attachment.
                try Task.checkCancellation()
                let url = directory.appendingPathComponent(attachment.identifier.uuidString.lowercased(), isDirectory: false)
                let written = try await AttachmentFileWriter.copy(to: url) { handler in
                    store.streamData(for: attachment, dataHandler: handler)
                }
                copies.append(HKAttachment.FileCopy(
                    attachment: attachment,
                    url: url,
                    byteCount: written.byteCount,
                    sha1: written.sha1,
                    sha256: written.sha256
                ))
            }
        } catch {
            for copy in copies {
                try? FileManager.default.removeItem(at: copy.url)
            }
            throw error
        }
        return copies
    }
}

#endif

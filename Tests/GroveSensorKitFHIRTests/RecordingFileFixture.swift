//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Owns caller files. Retain the fixture through file operations; its URLs do not retain it.
final class RecordingFileFixture: Sendable {
    let directory: URL
    let source: URL

    init(_ data: Data) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("recording-file-test-\(UUID().uuidString)", isDirectory: true)
        source = directory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do { try data.write(to: source) } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

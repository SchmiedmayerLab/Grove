//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import Testing


@Suite
struct RecordingFileProducerTests {
    private enum Failure: Error {
        case interrupted
    }

    @Test
    func bufferedProductionPreservesBoundariesAndRefusesPartialSuccess() throws {
        let chunk = Data(repeating: 17, count: 32_769)
        let count = chunk.count * 3
        let file = try RecordingFile.stage(maximumByteCount: count) { append in
            for _ in 0..<3 { try append(chunk) }
        }
        var actual = Data()
        try file.readChunks { actual.append($0) }
        #expect(actual == chunk + chunk + chunk)
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try RecordingFile.stage(maximumByteCount: count - 1) { append in
                for _ in 0..<3 { try append(chunk) }
            }
        }
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try RecordingFile.stage(maximumByteCount: 1) { append in
                try append(Data([1]))
                do { try append(Data([2])) } catch { }
            }
        }
        #expect(throws: Failure.interrupted) {
            try RecordingFile.stage(maximumByteCount: count) { append in
                try append(chunk)
                throw Failure.interrupted
            }
        }
        #expect(throws: RecordingFile.FileError.emptySource) {
            try RecordingFile.stage(maximumByteCount: count) { _ in }
        }
    }
}

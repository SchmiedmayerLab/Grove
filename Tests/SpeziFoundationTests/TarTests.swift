//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation
import Testing


@Suite
struct TarTests {
    private let sampleEntries: [Tar.Entry] = [
        .directory("article"),
        .file("article/welcome.md", contents: Data("# Welcome".utf8)),
        .file("article/what is next.md", contents: Data("# Next".utf8)), // spaces are legal in a path
        .file("definition.json", contents: Data(#"{"schemaVersion":"0.14.0"}"#.utf8)),
        .file("empty", contents: Data())
    ]

    @Test
    func roundTripsEntries() throws {
        let archive = try Tar.archive(sampleEntries)
        let read = try Tar.entries(in: archive)
        #expect(read == sampleEntries)
    }

    @Test
    func archivingIsDeterministic() throws {
        let first = try Tar.archive(sampleEntries)
        let second = try Tar.archive(sampleEntries)
        #expect(first == second)
    }

    @Test
    func preservesArbitraryContentBytes() throws {
        // Content spanning multiple blocks and every byte value must survive the padding.
        let payload = Data((0..<2000).map { UInt8($0 % 256) })
        let read = try Tar.entries(in: Tar.archive([.file("blob", contents: payload)]))
        #expect(read == [.file("blob", contents: payload)])
    }

    @Test
    func rejectsAPathExceedingTheNameField() throws {
        let longPath = String(repeating: "a", count: 101)
        #expect(throws: Tar.TarError.self) {
            try Tar.archive([.file(longPath, contents: Data())])
        }
    }

    @Test
    func rejectsACorruptedHeaderChecksum() throws {
        var archive = try Tar.archive(sampleEntries)
        archive[archive.startIndex] = archive[archive.startIndex] &+ 1 // perturb the first name byte
        #expect(throws: Tar.TarError.self) {
            try Tar.entries(in: archive)
        }
    }

    @Test
    func rejectsAMissingEndMarker() throws {
        let archive = try Tar.archive(sampleEntries)
        let withoutMarker = archive.prefix(archive.count - 1024) // drop the two zero blocks
        #expect(throws: Tar.TarError.self) {
            try Tar.entries(in: Data(withoutMarker))
        }
    }

    @Test
    func rejectsTruncatedContent() throws {
        let archive = try Tar.archive([.file("blob", contents: Data(repeating: 7, count: 600))])
        let truncated = archive.prefix(512 + 512) // header plus only one of two content blocks
        #expect(throws: Tar.TarError.self) {
            try Tar.entries(in: Data(truncated))
        }
    }
}

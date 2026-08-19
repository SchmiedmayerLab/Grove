//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveSensorKitFHIR
import Testing


@Suite
struct SensorBatchArchiveTests {
    @Test
    func tarLayoutMatchesTheReferencesInsideIt() throws {
        var archive = SensorBatchArchive()
        try archive.addFile(path: "fhir/Observation.ndjson", data: Data("{}\n".utf8))
        try archive.addFile(path: "payloads/ecg/session-1.csv", data: Data("timestamp,uV\n0,1.0\n".utf8))
        // The paths are exactly what DocumentReference.content.attachment.url carries,
        // so a consumer that unpacks the archive resolves every reference locally.
        #expect(archive.paths == ["fhir/Observation.ndjson", "payloads/ecg/session-1.csv"])

        let tar = try archive.data(compression: .none)
        #expect(tar.count.isMultiple(of: 512), "a tar stream is a whole number of 512-byte blocks")
        #expect(tar.suffix(1024).allSatisfy { $0 == 0 }, "the stream ends with two zero blocks")
        let firstHeader = tar.prefix(512)
        let name = String(decoding: firstHeader.prefix(while: { $0 != 0 }), as: UTF8.self)
        #expect(name == "fhir/Observation.ndjson")
        // ustar magic identifies the format to every extractor.
        let magic = String(decoding: firstHeader[257..<262], as: UTF8.self)
        #expect(magic == "ustar")
        // The header checksum must match the sum of the header bytes.
        var header = Array(firstHeader)
        let recorded = Int(String(decoding: header[148..<154], as: UTF8.self), radix: 8)
        for index in 148..<156 {
            header[index] = 0x20
        }
        #expect(recorded == header.reduce(0) { $0 + Int($1) })
    }

    @Test
    func gzipStreamIsWellFormed() throws {
        var archive = SensorBatchArchive()
        let payload = Data(String(repeating: "sample,1.0\n", count: 500).utf8)
        try archive.addFile(path: "payloads/stream.csv", data: payload)
        let raw = try archive.data(compression: .none)
        let zipped = try archive.data(compression: .gzip)
        #expect(zipped.prefix(2) == Data([0x1F, 0x8B]), "gzip magic")
        #expect(zipped[2] == 0x08, "deflate method")
        #expect(zipped.count < raw.count, "compression must shrink a repetitive stream")
        // The trailer records the uncompressed size, which extractors verify.
        let size = zipped.suffix(4).enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * UInt32($1.offset))) }
        #expect(size == UInt32(raw.count))
    }

    @Test
    func compressionIsPluggable() throws {
        var archive = SensorBatchArchive()
        try archive.addFile(path: "payloads/stream.csv", data: Data("x".utf8))
        // Apple's SDK ships no zstd; an app supplies its own codec without changing
        // the archive layout.
        let marker = Data("ZSTD".utf8)
        let custom = try archive.data(compression: .custom(fileExtension: "zst") { marker + $0.prefix(4) })
        #expect(custom.prefix(4) == marker)
        #expect(SensorBatchArchive.Compression.gzip.fileExtension == "tar.gz")
        #expect(SensorBatchArchive.Compression.custom(fileExtension: "zst") { $0 }.fileExtension == "tar.zst")
    }
}

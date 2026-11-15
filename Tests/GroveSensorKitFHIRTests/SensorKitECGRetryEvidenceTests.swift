//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
import GroveFHIRContract
@testable import GroveSensorKit
import GroveSensorKitFHIR
import SensorKit
import Testing


@Suite
struct SensorKitECGRetryEvidenceTests {
    @available(iOS 17.4, *)
    @Test(arguments: ["start", "frequency", "lead", "guidance"])
    func sourceFactsOutsideNativePayloadChangeSupplement(field: String) throws {
        let first = try SensorKitPreparedStructuredRecord(electrocardiogram: session())
        let changed = try SensorKitPreparedStructuredRecord(electrocardiogram: session(changing: field))
        #expect(first.nativePayload == changed.nativePayload)
        #expect(first.retryEvidence == changed.retryEvidence)
        #expect(first.retryEvidenceSupplement.count == 32)
        #expect(first.retryEvidenceSupplement != changed.retryEvidenceSupplement)
    }

    @available(iOS 17.4, *)
    @Test
    func supplementMatchesExistingClientFramingWithoutChangingNativePayload() throws {
        let sample = session()
        let prepared = try SensorKitPreparedStructuredRecord(electrocardiogram: sample)
        var existing = Data()
        for word in [
            sample.startDate.timeIntervalSince1970.bitPattern,
            sample.frequency.converted(to: .hertz).value.bitPattern,
            UInt64(bitPattern: Int64(sample.lead.rawValue)),
            UInt64(bitPattern: Int64(sample.guidance.rawValue))
        ] {
            withUnsafeBytes(of: word.bigEndian) { existing.append(contentsOf: $0) }
        }
        #expect(prepared.retryEvidenceSupplement == existing)
        #expect(prepared.retryEvidence == prepared.nativePayload)
    }

    @available(iOS 17.4, *)
    @Test
    func filePreparationPreservesExactBytesAndSupplement() throws {
        let sample = session()
        let data = try SensorKitPreparedStructuredRecord(electrocardiogram: sample)
        let file = try SensorKitPreparedStructuredFile(electrocardiogram: sample, maximumByteCount: 4096)
        var bytes = Data()
        try file.file.readChunks { bytes.append($0) }
        #expect(bytes == data.nativePayload)
        #expect(file.retryEvidenceSupplement == data.retryEvidenceSupplement)
        var evidence = Data()
        try file.readRetryEvidenceChunks { evidence.append($0) }
        #expect(evidence == data.retryEvidence + data.retryEvidenceSupplement)
        try RegisteredRecordingFormat.nativeRecording.validatePayload(file.file, maximumByteCount: file.file.byteCount)
        #expect(throws: RecordingFile.FileError.byteLimitExceeded) {
            try SensorKitPreparedStructuredFile(electrocardiogram: sample, maximumByteCount: file.file.byteCount - 1)
        }
        let exact = try SensorKitPreparedStructuredFile(electrocardiogram: sample, maximumByteCount: file.file.byteCount)
        #expect(exact.file.byteCount == file.file.byteCount)
    }

    @available(iOS 17.4, *)
    private func session(changing field: String = "") -> SensorKitECGSession {
        SensorKitECGSession(
            startDate: Date(timeIntervalSince1970: field == "start" ? 101 : 100),
            sessionIdentifier: "synthetic-ecg-session",
            sessionStates: [.begin, .active, .end],
            frequency: Measurement(value: field == "frequency" ? 256 : 512, unit: .hertz),
            lead: field == "lead" ? .leftArmMinusRightArm : .rightArmMinusLeftArm,
            guidance: field == "guidance" ? .unguided : .guided,
            batches: [
                .init(offset: 0, samples: [.init(flags: [], voltage: Measurement(value: 1, unit: .microvolts))])
            ]
        )
    }
}
#endif

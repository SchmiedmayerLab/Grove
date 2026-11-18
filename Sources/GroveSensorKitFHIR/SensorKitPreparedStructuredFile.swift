//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

public import Foundation
public import GroveFHIRContract
public import GroveSensorKit
import SensorKit


/// File-backed native evidence with the same bytes and retry facts as the structured Data preparation.
/// The native SDK sample remains caller-owned; this avoids a second complete JSON representation in memory.
public struct SensorKitPreparedStructuredFile: Sendable {
    private enum ECGKey: String, CaseIterable {
        case batches
        case sessionIdentifier
        case sessionStates
    }

    private enum ECGBatchKey: String, CaseIterable {
        case offsetSeconds
        case samples
    }

    private struct ECGSampleEvidence: Encodable {
        let flags: UInt
        let microvolts: Double
    }

    /// The native recording.
    public let file: RecordingFile
    private let retryEvidenceSupplement: Data
    private let makeRecord: @Sendable (SensorKitSourceRecordID, SensorKitNativeRecording) throws -> SensorKitRecord

    init(
        file: RecordingFile,
        retryEvidenceSupplement: Data = Data(),
        makeRecord: @escaping @Sendable (SensorKitSourceRecordID, SensorKitNativeRecording) throws -> SensorKitRecord
    ) {
        self.file = file
        self.retryEvidenceSupplement = retryEvidenceSupplement
        self.makeRecord = makeRecord
    }

    /// Writes each ECG sample independently while preserving the established JSON field order and numeric representation.
    @available(iOS 17.4, *)
    public init(electrocardiogram session: SensorKitECGSession, maximumByteCount: Int) throws {
        self.file = try Self.ecgFile(session, maximumByteCount: maximumByteCount)
        self.retryEvidenceSupplement = session.groveRetryEvidenceSupplement
        self.makeRecord = { sourceID, native in
            .electrocardiogram(try SensorKitECGRecord(sourceRecordID: sourceID, session: session, nativeRecording: native))
        }
    }

    /// Reads the exact source facts a retry compares, the bytes of
    /// ``SensorKitPreparedStructuredRecord/retryEvidence``: the native JSON, followed by any fact the JSON doesn't
    /// state.
    public func readRetryEvidenceChunks(_ consume: (Data) throws -> Void) throws {
        try file.readChunks(consume)
        try Task.checkCancellation()
        if !retryEvidenceSupplement.isEmpty { try consume(retryEvidenceSupplement) }
    }

    /// Builds the FHIR input, referencing the file at an archive-relative path.
    ///
    /// This module generated the JSON, so the file is attached without being parsed again to check it.
    ///
    /// - Parameters:
    ///   - sourceRecordID: The identity of the source sample.
    ///   - title: The attachment title.
    ///   - sidecarPath: The archive-relative path the file is stored at.
    ///   - admission: The caller's authorization to attach the native recording.
    public func sensorKitRecord(
        sourceRecordID: SensorKitSourceRecordID, title: String, sidecarPath: String, admission: RecordingPayloadAdmission
    ) throws -> SensorKitRecord {
        let native = try SensorKitNativeRecording(
            title: title, format: .nativeRecording, payload: .file(path: sidecarPath, contents: file), admission: admission
        ) { _ in }
        return try makeRecord(sourceRecordID, native)
    }
}


extension SensorKitPreparedStructuredFile {
    @available(iOS 17.4, *)
    private static func ecgFile(_ session: SensorKitECGSession, maximumByteCount: Int) throws -> RecordingFile {
        let writer = SensorKitJSONFileEncoding()
        return try RecordingFile.stage(maximumByteCount: min(maximumByteCount, RegisteredRecordingFormat.maximumDecodedPayloadByteCount)) { append in
            try writer.object(ECGKey.allCases, name: \.rawValue, append: append) { key in
                switch key {
                case .batches:
                    try writer.array(session.batches, append: append) { batch in
                        try writer.object(ECGBatchKey.allCases, name: \.rawValue, append: append) { key in
                            switch key {
                            case .offsetSeconds: try writer.value(batch.offset, append: append)
                            case .samples:
                                try writer.array(batch.samples, append: append) { sample in
                                    try writer.value(ECGSampleEvidence(
                                        flags: sample.flags.rawValue, microvolts: sample.voltage.converted(to: .microvolts).value
                                    ), append: append)
                                }
                            }
                        }
                    }
                case .sessionIdentifier: try writer.value(session.sessionIdentifier, append: append)
                case .sessionStates: try writer.value(session.sessionStates.map(\.rawValue), append: append)
                }
            }
        }
    }
}


#endif

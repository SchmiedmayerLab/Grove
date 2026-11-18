//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// This validator intentionally keeps the closed payload grammar in one exhaustive switch.
// swiftlint:disable cyclomatic_complexity function_body_length

public import Foundation
public import GroveFHIRContract
import ModelsR4


/// Why bytes do not satisfy the payload grammar named by a registered format code.
public enum RegisteredRecordingPayloadError: Error, Equatable, Sendable {
    case payloadLimitExceeded
    case invalidFHIRJSON
    case invalidJSON
    case JSONByteOrderMark
    case expectedJSONObjectOrArray
    case duplicateJSONMember(String)
    case nonFiniteJSONNumber
    /// The bytes are not the format's registered CSV; the reader error names the first violation, such as a field quoted
    /// although the canonical quoting leaves it unquoted.
    case invalidTabularPayload(RecordingCSVReader.ReaderError)
    case invalidPhotoplethysmogramPayload
    case expectedR4CollectionBundle
    case missingBundleTimestamp
    case emptyCollectionBundle
    case missingEntryFullURL(index: Int)
    case duplicateEntryFullURL(String)
    case missingEntryResource(index: Int)
    case forbiddenEntrySearch(index: Int)
    case forbiddenEntryRequest(index: Int)
    case forbiddenEntryResponse(index: Int)
}


extension RegisteredRecordingFormat {
    /// JSON and PPG validation decodes the complete payload, limited to 64 MiB before allocation.
    /// CSV uses bounded incremental validation; clinical documents are carried byte-preserved.
    public static let maximumDecodedPayloadByteCount = 64 * 1024 * 1024

    private var requiresWholePayloadDecoding: Bool {
        csvColumns == nil && self != .clinicalDocument
    }

    /// Validates a recording file against this format's grammar within the caller's byte limit.
    ///
    /// A CSV is validated in bounded chunks, retaining one bounded row. JSON, FHIR and PPG payloads are decoded as a
    /// whole and stay within ``maximumDecodedPayloadByteCount`` as well. The caller separately verifies the source
    /// digests, the media type, the consent and the clinical graph.
    ///
    /// - Parameters:
    ///   - file: The recording file.
    ///   - maximumByteCount: The most bytes the file may hold, between 1 and `Int32.max`.
    /// - Throws: A ``RegisteredRecordingPayloadError``, a `RecordingFile.FileError` or `CancellationError`.
    public func validatePayload(_ file: RecordingFile, maximumByteCount: Int) throws {
        try Self.validateByteCount(file.byteCount, maximumByteCount: maximumByteCount)
        try validatePayload(file)
    }

    /// Validates bytes already in memory against this format's grammar within the caller's byte limit.
    ///
    /// Payloads that are decoded as a whole stay within ``maximumDecodedPayloadByteCount`` as well.
    ///
    /// - Parameters:
    ///   - bytes: The payload.
    ///   - maximumByteCount: The most bytes the payload may hold, between 1 and `Int32.max`.
    public func validatePayload(_ bytes: Data, maximumByteCount: Int) throws(RegisteredRecordingPayloadError) {
        try Self.validateByteCount(bytes.count, maximumByteCount: maximumByteCount)
        try validatePayload(bytes)
    }

    /// Both entry points admit at most the caller's limit, which an attachment's `Int32` size bounds.
    private static func validateByteCount(_ byteCount: Int, maximumByteCount: Int) throws(RegisteredRecordingPayloadError) {
        guard (1...Int(Int32.max)).contains(maximumByteCount), byteCount <= maximumByteCount else {
            throw .payloadLimitExceeded
        }
    }

    func validatePayloadSize(_ byteCount: Int) throws(RegisteredRecordingPayloadError) {
        guard !requiresWholePayloadDecoding || byteCount <= Self.maximumDecodedPayloadByteCount else { throw .payloadLimitExceeded }
    }

    func validatePayload(_ file: RecordingFile) throws {
        try validatePayloadSize(file.byteCount)
        if csvColumns != nil {
            do {
                var stream = try RecordingCSVReader.Stream(format: self)
                try file.readChunks { try stream.read($0) }
                try stream.finish()
            } catch let error as RecordingCSVReader.ReaderError {
                throw RegisteredRecordingPayloadError.invalidTabularPayload(error)
            }
        } else if requiresWholePayloadDecoding {
            try validatePayload(file.decodedPayload(maximumByteCount: Self.maximumDecodedPayloadByteCount))
        }
    }

    /// Resolves an explicit media type or derives the sole registered representation.
    func resolveContentType(_ contentType: String?) -> String? {
        if let contentType {
            return registeredContentTypes.contains(contentType) ? contentType : nil
        }
        return registeredContentType
    }

    /// Validates the registered formats whose code makes a complete FHIR-shape assertion.
    ///
    /// Opaque and tabular formats have their own typed writers/readers. A FHIR collection payload
    /// is caller-supplied JSON, so its constructor must prove the closed envelope rather than rely
    /// on the media type alone.
    func validatePayload(_ data: Data) throws(RegisteredRecordingPayloadError) {
        try validatePayloadSize(data.count)
        switch self {
        case .nativeRecording, .providerRecording:
            do {
                var scanner = StrictJSONScanner(data)
                try scanner.validate()
            } catch {
                switch error {
                case .byteOrderMark: throw .JSONByteOrderMark
                case .scalarRoot: throw .expectedJSONObjectOrArray
                case .duplicateMember(let name): throw .duplicateJSONMember(name)
                case .nonFiniteNumber: throw .nonFiniteJSONNumber
                case .invalidJSON, .nestingLimit: throw .invalidJSON
                }
            }
        case .photoplethysmogramSamples:
            do {
                _ = try SensorKitPPGRecording(data: data)
            } catch {
                throw .invalidPhotoplethysmogramPayload
            }
        case .ambientLightSamples, .ambientPressureSamples, .beatIntervalSeries, .heartRateSamples,
             .locationTrackSamples, .odometerSamples, .pedometerSamples, .triaxialAccelerationSamples,
             .triaxialRotationSamples, .wristTemperatureSamples:
            do {
                var stream = try RecordingCSVReader.Stream(format: self)
                try stream.read(data)
                try stream.finish()
            } catch {
                throw .invalidTabularPayload(error)
            }
        case .clinicalDocument:
            // The clinical document is carried byte-preserved: its grammar belongs to the issuing
            // standard, and Grove asserts its identity and media type rather than re-parsing it.
            break
        case .fhirCollectionBundle:
            let bundle: ModelsR4.Bundle
            do {
                bundle = try JSONDecoder().decode(ModelsR4.Bundle.self, from: data)
            } catch {
                throw .invalidFHIRJSON
            }
            guard bundle.type.value == .collection else {
                throw .expectedR4CollectionBundle
            }
            guard bundle.timestamp != nil else {
                throw .missingBundleTimestamp
            }
            guard let entries = bundle.entry, !entries.isEmpty else {
                throw .emptyCollectionBundle
            }
            var fullURLs: Set<String> = []
            for (index, entry) in entries.enumerated() {
                guard let fullURL = entry.fullUrl?.value?.url.absoluteString, !fullURL.isEmpty else {
                    throw .missingEntryFullURL(index: index)
                }
                guard fullURLs.insert(fullURL).inserted else {
                    throw .duplicateEntryFullURL(fullURL)
                }
                guard entry.resource != nil else {
                    throw .missingEntryResource(index: index)
                }
                guard entry.search == nil else {
                    throw .forbiddenEntrySearch(index: index)
                }
                guard entry.request == nil else {
                    throw .forbiddenEntryRequest(index: index)
                }
                guard entry.response == nil else {
                    throw .forbiddenEntryResponse(index: index)
                }
            }
        case .fhirResource:
            do {
                try FHIRJSONResourcePayload.validate(data)
            } catch {
                throw .invalidFHIRJSON
            }
        }
    }
}

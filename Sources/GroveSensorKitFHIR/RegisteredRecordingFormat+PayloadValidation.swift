//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// This validator intentionally keeps the closed payload grammar in one exhaustive switch.
// swiftlint:disable cyclomatic_complexity function_body_length

import Foundation
import GroveFHIRContract
import ModelsR4


/// Why bytes do not satisfy the payload grammar named by a registered format code.
public enum RegisteredRecordingPayloadError: Error, Equatable, Sendable {
    case invalidFHIRJSON
    case invalidJSON
    case JSONByteOrderMark
    case expectedJSONObjectOrArray
    case duplicateJSONMember(String)
    case nonFiniteJSONNumber
    case invalidTabularPayload
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
        switch self {
        case .nativeRecording, .providerRecording:
            do {
                var validator = StrictJSONEnvelopeValidator(data)
                try validator.validate()
            } catch let error as StrictJSONEnvelopeError {
                switch error {
                case .byteOrderMark: throw .JSONByteOrderMark
                case .scalarRoot: throw .expectedJSONObjectOrArray
                case .duplicateMember(let name): throw .duplicateJSONMember(name)
                case .nonFiniteNumber: throw .nonFiniteJSONNumber
                case .invalidJSON, .nestingLimit: throw .invalidJSON
                }
            } catch {
                throw .invalidJSON
            }
        case .photoplethysmogramSamples:
            do {
                _ = try SensorKitPPGRecording(data: data)
            } catch {
                throw .invalidPhotoplethysmogramPayload
            }
        case let format where Self.tabularFormats.contains(format):
            do {
                _ = try RecordingCSVReader(data, format: format)
            } catch {
                throw .invalidTabularPayload
            }
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
        default:
            break
        }
    }
}

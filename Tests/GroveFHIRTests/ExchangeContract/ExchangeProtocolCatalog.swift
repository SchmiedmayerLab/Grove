//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import Testing


let groveFHIRRoot: URL = {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        repositoryRoot.appendingPathComponent(".fhir/grove-fhir", isDirectory: true),
        repositoryRoot.deletingLastPathComponent().appendingPathComponent("grove-fhir", isDirectory: true)
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("catalog").path) } ?? candidates[0]
}()

let groveFHIRIsAvailable = FileManager.default.fileExists(
    atPath: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json").path
)


/// The parts of `catalog/exchange-protocol.json` the contract's vector tests read, from the grove-fhir working tree.
struct ExchangeProtocolCatalog: Decodable {
    struct IdentitySystem: Decodable {
        let identityKind: String
        let system: String
    }

    struct Identity: Decodable {
        let id: String
        let identityKind: String
        let components: [String]
        let value: String
    }

    struct InvalidIdentity: Decodable {
        let id: String
        let identityKind: String
        let components: [String]
        let expectedError: String
    }

    struct FullURL: Decodable {
        let id: String
        let system: String
        let value: String
        let fullUrl: String
    }

    struct CanonicalJSON: Decodable {
        let id: String
        let input: String
        let canonical: String
        let sha256: String
    }

    struct InvalidCanonicalJSON: Decodable {
        let id: String
        let inputHex: String
        let expectedError: String
    }

    struct RecordContent: Decodable {
        let id: String
        let provenance: String
        let outputs: [String]
        let recordContentDigest: String
    }

    struct KeyFingerprint: Decodable {
        let id: String
        let subjectSystem: String
        let subjectValue: String
        let fingerprint: String
        let keyIdSuffix: String
    }

    struct Vectors: Decodable {
        let keyHex: String
        let keyId: String
        let epoch: String
        let identitySystems: [IdentitySystem]
        let identities: [Identity]
        let invalidIdentities: [InvalidIdentity]
        let fullUrls: [FullURL]
        let canonicalJson: [CanonicalJSON]
        let invalidCanonicalJson: [InvalidCanonicalJSON]
        let recordContents: [RecordContent]
        let keyFingerprint: [KeyFingerprint]
    }

    struct Diagnostic: Decodable {
        let code: String
        let reason: String
        let severity: ProducerDiagnostic.Severity?
    }

    struct IdentityKind: Decodable {
        let kind: String
        let components: [String]
    }

    struct OpaqueIdentity: Decodable {
        let identityKinds: [IdentityKind]
    }

    static let deploymentRoot: IdentifierSystem = "https://study.example.org/fhir"

    static var current: Self {
        get throws {
            try JSONDecoder().decode(
                Self.self,
                from: Data(contentsOf: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json"))
            )
        }
    }

    let testVectors: Vectors
    let producerDiagnostics: [Diagnostic]
    let opaqueIdentity: OpaqueIdentity
}


extension ExchangeProtocolCatalog.Vectors {
    /// The identity scope of the published test key.
    var scope: OpaqueIdentityScope {
        get throws {
            let epoch = try KeyEpoch(epoch)
            let systems = try DeploymentIdentifierSystems.derived(
                root: ExchangeProtocolCatalog.deploymentRoot,
                keyID: keyId,
                epoch: epoch
            )
            return try OpaqueIdentityScope.conformanceTesting(systems: systems, keyID: keyId, epoch: epoch)
        }
    }
}


extension Data {
    init(hex: String) throws {
        self.init()
        var digits = hex[...]
        while !digits.isEmpty {
            append(try #require(UInt8(digits.prefix(2), radix: 16)))
            digits = digits.dropFirst(2)
        }
    }
}


extension LosslessJSONValue {
    // swiftlint:disable:next discouraged_optional_collection
    var object: [String: LosslessJSONValue]? {
        guard case .object(let members) = self else {
            return nil
        }
        return members
    }

    // swiftlint:disable:next discouraged_optional_collection
    var array: [LosslessJSONValue]? {
        guard case .array(let elements) = self else {
            return nil
        }
        return elements
    }

    var string: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var resourceType: String? {
        object?["resourceType"]?.string
    }

    /// A Bundle entry's resource.
    var resource: LosslessJSONValue? {
        object?["resource"]
    }

    /// An Identifier's system and value.
    var businessIdentifier: BusinessIdentifier? {
        guard let system = object?["system"]?.string, let value = object?["value"]?.string else {
            return nil
        }
        return try? BusinessIdentifier(system: IdentifierSystem(system), value: value)
    }

    /// A Bundle entry's key, as `grove-exchange-entry-key` states it.
    var entryKey: BusinessIdentifier? {
        object?["extension"]?.array?.first { $0.object?["url"]?.string?.hasSuffix("grove-exchange-entry-key") == true }?
            .object?["valueIdentifier"]?.businessIdentifier
    }

    /// A Provenance's source record, as `entity.what.identifier` states it.
    var sourceRecord: BusinessIdentifier? {
        object?["entity"]?.array?.first?.object?["what"]?.object?["identifier"]?.businessIdentifier
    }
}

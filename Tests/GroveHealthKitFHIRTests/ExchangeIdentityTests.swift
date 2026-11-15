//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation
@testable import GroveFHIRContract
import ModelsR4
import Testing

@Suite
struct GroveFHIRExchangeIdentityTests {
    private static var scope: OpaqueIdentityScope {
        get throws {
            try OpaqueIdentityScope.conformanceTesting(
                systems: DeploymentIdentifierSystems(
                    sourceRecord: "https://study.example.org/fhir/NamingSystem/source-record-test-key-1",
                    sourceOutput: "https://study.example.org/fhir/NamingSystem/source-output-test-key-1",
                    writerRecord: "https://study.example.org/fhir/NamingSystem/writer-record-test-key-1",
                    providerRecord: "https://study.example.org/fhir/NamingSystem/provider-record-test-key-1",
                    providerOutput: "https://study.example.org/fhir/NamingSystem/provider-output-test-key-1",
                    sourceArtifact: "https://study.example.org/fhir/NamingSystem/source-artifact-test-key-1",
                    providerArtifact: "https://study.example.org/fhir/NamingSystem/provider-artifact-test-key-1",
                    sourceContext: "https://study.example.org/fhir/NamingSystem/source-context-test-key-1",
                    recordingDevice: "https://study.example.org/fhir/NamingSystem/recording-device-test-key-1",
                    deviceSnapshot: "https://study.example.org/fhir/NamingSystem/device-snapshot-test-key-1",
                    contextSnapshot: "https://study.example.org/fhir/NamingSystem/context-snapshot-test-key-1",
                    recordVersion: "https://study.example.org/fhir/NamingSystem/record-version-test-key-1",
                    recordRetraction: "https://study.example.org/fhir/NamingSystem/record-retraction-test-key-1",
                    deviceLocalIdentifier: "https://study.example.org/fhir/NamingSystem/device-local-identifier"
                ),
                keyID: "test-key",
                epoch: KeyEpoch(1)
            )
        }
    }

    private static func identifier(_ system: String, _ value: String) throws -> BusinessIdentifier {
        try BusinessIdentifier(system: IdentifierSystem(system), value: value)
    }

    @Test("Source context matches the shared medication vector")
    func sourceContextVector() throws {
        let identifier = try Self.scope.sourceContext(
            adapterID: "healthkit",
            contextType: "medication-health-concept",
            repositoryScope: BusinessIdentifier(
                system: "urn:uuid:1f5c58aa-6ec6-4e79-a682-829a9debd3f5",
                value: "default"
            ),
            nativeContextID: "2f8a51c6-9d34-4e07-b2f1-63c8ad905e12"
        )
        #expect(identifier.role == .sourceContext)
        #expect(identifier.value == "v0:test-key:1:YTeSyVMN8VDKaIp7rLq6h9HfDIypiKcwO-nFqCJA8Dk")
    }

    @Test("Matches the normative Unicode and separator source-record vector")
    func sourceRecordVector() throws {
        let identifier = try Self.scope.sourceRecord(
            adapterID: "health-connect",
            sourceType: "RestingHeartRateRecord",
            repositoryScope: BusinessIdentifier(
                system: "urn:uuid:1f5c58aa-6ec6-4e79-a682-829a9debd3f5",
                value: "default"
            ),
            nativeRecordID: "record|東京"
        ).identifier
        #expect(identifier.value == "v0:test-key:1:BDCkwCFA2Wg4-fHVRsy4L0JWYuvQknZkCTXL4Ct01IQ")
        #expect(identifier.role == .sourceRecord)
    }

    @Test("A source-output HMAC has exactly one role and one discriminator frame")
    func sourceOutputVector() throws {
        let record = try Self.scope.sourceRecord(
            adapterID: "health-connect",
            sourceType: "HeartRateRecord",
            repositoryScope: BusinessIdentifier(
                system: "urn:uuid:1f5c58aa-6ec6-4e79-a682-829a9debd3f5",
                value: "default"
            ),
            nativeRecordID: "record-heart-001"
        )
        let identifier = try record.output(role: "sample", discriminator: "2026-08-19T10:30:00.000000000Z|0")
        #expect(identifier.value == "v0:test-key:1:MYPFjAMsSt0suOqpN29y_KjG__sagIpCbYKAfVKx6ck")
        #expect(identifier.role == .sourceOutput)
    }

    @Test("A record identity prints its opaque identifier, never the key or the native record identifier")
    func recordIdentityDebugDescription() throws {
        let source = try Self.scope.sourceRecord(
            adapterID: "healthkit",
            sourceType: "HKQuantityTypeIdentifierHeartRate",
            repositoryScope: Self.identifier("https://store.example.org", "default"),
            nativeRecordID: "native-record-001"
        )
        let provider = try Self.scope.providerRecord(
            providerCode: .oura,
            sourceType: "heart-rate",
            providerScope: Self.identifier("https://accounts.example.org", "patient"),
            nativeRecordID: "native-record-002"
        )
        #expect(String(reflecting: source) == "SourceRecordIdentity(identifier: \(source.identifier.value))")
        #expect(String(reflecting: provider) == "SourceRecordIdentity(identifier: \(provider.identifier.value))")
    }

    @Test("Matches complete-pair provider, writer, and recording-device vectors")
    func completePairVectors() throws {
        let provider = try Self.scope.providerRecord(
            providerCode: .withings,
            sourceType: "measure",
            providerScope: Self.identifier("https://accounts.example.org", "patient|α"),
            nativeRecordID: "17348211"
        ).identifier
        let panel = try Self.scope.providerRecord(
            providerCode: .withings,
            sourceType: "getmeas:9+10",
            providerScope: Self.identifier("https://accounts.example.org", "patient|α"),
            nativeRecordID: "17348211"
        )
        let recording = try Self.scope.providerRecord(
            providerCode: .googleHealthAPI,
            sourceType: "heart-rate",
            providerScope: Self.identifier("https://accounts.example.org", "patient|α"),
            nativeRecordID: "recording-001"
        )
        let providerOutput = try panel.output(role: "blood-pressure-panel", discriminator: "single")
        let providerArtifact = try recording.artifact(formatCode: "provider-recording", partIndex: 0)
        let writer = try Self.scope.writerRecord(
            subject: Self.identifier("https://study.example.org/fhir/identifiers/participant", "participant-001"),
            writerApplication: Self.identifier("https://applications.example.org", "com.withings.wiscale2"),
            writerRecordID: "logical-record-001"
        )
        let recordingDevice = try Self.scope.recordingDevice(
            adapterID: "healthkit",
            subject: Self.identifier("https://study.example.org/participants", "participant-001"),
            tokenScope: "com.example.watch-app",
            stableUnitToken: "watch-unit-token-001"
        )
        #expect(provider.value == "v0:test-key:1:qfmx1ajnVg_rNE8qiL_hIAWI8GtbVpRtf6T2RWREezM")
        #expect(providerOutput.value == "v0:test-key:1:mum-FTSsu6Kv_QBFNSjcFuznTp5C6D3QnrQ6iwm23Ec")
        #expect(providerArtifact.value == "v0:test-key:1:0LxvhsWmRngwxPPMqWk7--4qTN8Wa1j-oTbGuMCCgrA")
        #expect(writer.value == "v0:test-key:1:t3yJ50PlC4YfvU2A4qhUgG17VfFJ_QhTgltKtosdl7w")
        #expect(recordingDevice.value == "v0:test-key:1:EGbYNz6iVTYGCXRIUR-1TVJeTAVmPhsQmT6UF-dC3q0")
    }

    @Test("Matches normative record-version, record-retraction, and UUIDv5 vectors")
    func graphKeyVectors() throws {
        let version = try BusinessIdentifier(
            system: "https://study.example.org/fhir/NamingSystem/grove-record-version-v0/test-key/1",
            value: "v0:test-key:1:xjbzwZqYyBE1boHxzOoS09iLXEMrvo0o8dpxtlwPQhE"
        )
        let retraction = try BusinessIdentifier(
            system: "https://study.example.org/fhir/NamingSystem/grove-record-retraction-v0/test-key/1",
            value: "v0:test-key:1:0JJ96w-JxTpK7Bb-910L_61f3KJdI8Cr4eSGTpJ7L7o"
        )
        let unicode = try BusinessIdentifier(
            system: "https://xn--fsq.example/%E8%AD%98%E5%88%A5%E5%AD%90",
            value: "café|東京"
        )
        #expect(try version.fullURLString == "urn:uuid:af53df9f-24e4-5773-9301-a3887fdf2f57")
        #expect(try retraction.fullURLString == "urn:uuid:03e766bb-9cc6-51b2-b67e-e8902e01513f")
        #expect(try unicode.fullURLString == "urn:uuid:d35e4203-71f6-595c-bd1b-306b8414974e")
    }

    @Test("A Grove identifier-role coding without a code fails closed")
    func rejectsMissingIdentifierRoleCode() {
        let identifier = Identifier(
            system: "https://study.example.org/fhir/NamingSystem/source-record-test-key-1",
            type: CodeableConcept(coding: [Coding(system: Canonicals.identifierRoleCodeSystem)]),
            value: "v0:test-key:1:BDCkwCFA2Wg4-fHVRsy4L0JWYuvQknZkCTXL4Ct01IQ"
        )
        #expect(throws: ExchangeIdentityError.invalidIdentifierRole("missing")) {
            try RoledIdentifier(identifier)
        }
    }

    @Test("Length framing distinguishes delimiter and field-boundary collisions")
    func lengthFramingIsUnambiguous() throws {
        #expect(try Data(lengthFramedUTF8: ["a|b", "c"]) != Data(lengthFramedUTF8: ["a", "b|c"]))
        #expect(try Data(lengthFramedUTF8: ["é"]) != Data(lengthFramedUTF8: ["e", "\u{301}"]))
        #expect(try Data(lengthFramedUTF8: [""]) == Data([0, 0, 0, 0]))
    }

    @Test("The published conformance key cannot initialize a production identity scope")
    func rejectsPublishedConformanceKeyInProductionInitializer() throws {
        #expect(throws: ExchangeIdentityError.publishedConformanceKeyProhibited) {
            try OpaqueIdentityScope(
                systems: Self.scope.systems,
                keyID: "must-not-ship",
                epoch: KeyEpoch(1),
                key: SymmetricKey(data: Data((0...31).map(UInt8.init)))
            )
        }
    }
}

extension GroveFHIRExchangeIdentityTests {
    @Test("Typed identity constructors reject every semantically required empty component")
    func typedIdentityComponentsAreNonempty() throws {
        let repository = try BusinessIdentifier(system: "https://example.org/repository", value: "scope")
        let application = try BusinessIdentifier(system: "https://example.org/apps", value: "app")
        let subject = try BusinessIdentifier(system: "https://example.org/subjects", value: "subject")
        expectEmptySourceComponents(repository: repository)
        #expect(Set(OpaqueIdentityScope.ProviderCode.allCases.map(\.rawValue)) == ["google-health-api", "oura", "withings"])
        for providerCode in OpaqueIdentityScope.ProviderCode.allCases.map(\.rawValue) {
            expectProviderKindRequired(providerCode, repository: repository)
        }
        try expectEmptyDerivedComponents(repository: repository, application: application, subject: subject)
        // The protocol requires nonempty Unicode strings, not a global whitespace normalization.
        #expect(try Self.scope.sourceRecord(
            adapterID: "adapter",
            sourceType: "type",
            repositoryScope: repository,
            nativeRecordID: " "
        ).identifier.role == .sourceRecord)
    }

    private func expectEmptySourceComponents(repository: BusinessIdentifier) {
        #expect(throws: ExchangeIdentityError.emptyComponent("source-record.adapter-id")) {
            try Self.scope.sourceRecord(adapterID: "", sourceType: "type", repositoryScope: repository, nativeRecordID: "id")
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("source-record.source-type")) {
            try Self.scope.sourceRecord(adapterID: "adapter", sourceType: "", repositoryScope: repository, nativeRecordID: "id")
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("source-record.native-record-id")) {
            try Self.scope.sourceRecord(adapterID: "adapter", sourceType: "type", repositoryScope: repository, nativeRecordID: "")
        }
    }

    private func expectEmptyDerivedComponents(
        repository: BusinessIdentifier,
        application: BusinessIdentifier,
        subject: BusinessIdentifier
    ) throws {
        let record = try Self.scope.sourceRecord(
            adapterID: "adapter",
            sourceType: "type",
            repositoryScope: repository,
            nativeRecordID: "id"
        )
        #expect(throws: ExchangeIdentityError.emptyComponent("source-output.output-role")) {
            try record.output(role: "", discriminator: "single")
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("source-output.output-discriminator")) {
            try record.output(role: "primary", discriminator: "")
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("writer-record.writer-record-id")) {
            try Self.scope.writerRecord(subject: subject, writerApplication: application, writerRecordID: "")
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("source-artifact.format-code")) {
            try record.artifact(formatCode: "", partIndex: 0)
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("source-context.context-type")) {
            try Self.scope.sourceContext(
                adapterID: "adapter", contextType: "", repositoryScope: repository, nativeContextID: "id"
            )
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("source-context.native-context-id")) {
            try Self.scope.sourceContext(
                adapterID: "adapter", contextType: "context", repositoryScope: repository, nativeContextID: ""
            )
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("recording-device.stable-unit-token")) {
            try Self.scope.recordingDevice(adapterID: "adapter", subject: subject, tokenScope: "writer", stableUnitToken: "")
        }
        #expect(throws: ExchangeIdentityError.emptyComponent("recording-device.token-scope")) {
            try Self.scope.recordingDevice(adapterID: "adapter", subject: subject, tokenScope: "", stableUnitToken: "token")
        }
    }

    private func expectProviderKindRequired(_ providerCode: String, repository: BusinessIdentifier) {
        #expect(throws: ExchangeIdentityError.providerKindRequired(providerCode)) {
            try Self.scope.sourceRecord(
                adapterID: providerCode,
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id"
            )
        }
    }

    @Test("The closed identity-kind domain publishes the protocol's exact arities")
    func identityKindArities() {
        #expect(Dictionary(uniqueKeysWithValues: OpaqueIdentityKind.allCases.map {
            ($0.rawValue, $0.componentCount)
        }) == [
            "source-record": 5,
            "source-output": 7,
            "writer-record": 5,
            "provider-record": 5,
            "provider-output": 7,
            "source-artifact": 7,
            "provider-artifact": 7,
            "source-context": 5,
            "recording-device": 5,
            "device-snapshot": 4,
            "context-snapshot": 4,
            "record-version": 3,
            "record-retraction": 2
        ])
    }

    @Test("Protocol decimal coordinates have canonical spelling and no UInt64 ceiling")
    func unboundedProtocolDecimals() throws {
        let aboveUInt64 = "18446744073709551616"
        let wideEpochScope = try OpaqueIdentityScope(
            systems: Self.scope.systems,
            keyID: "wide-epoch",
            epoch: KeyEpoch(aboveUInt64),
            key: SymmetricKey(data: Data(repeating: 0x43, count: 32))
        )
        let wideEpochIdentity = try wideEpochScope.sourceRecord(
            adapterID: "healthkit",
            sourceType: "HKQuantityTypeIdentifierHeartRate",
            repositoryScope: BusinessIdentifier(system: "https://store.example.org", value: "default"),
            nativeRecordID: "record-001"
        ).identifier
        let deviceUsage = try Self.scope.sourceRecord(
            adapterID: "sensorkit",
            sourceType: "device-usage",
            repositoryScope: BusinessIdentifier(system: "https://store.example.org", value: "default"),
            nativeRecordID: "record-001"
        )
        let artifact = try deviceUsage.artifact(formatCode: "native-recording", partIndex: CanonicalNonnegativeDecimal(aboveUInt64))
        #expect(wideEpochScope.epoch.rawValue == aboveUInt64)
        #expect(wideEpochIdentity.value.hasPrefix("v0:wide-epoch:\(aboveUInt64):"))
        #expect(ExchangeIdentity.isCanonicalOpaqueIdentifierValue(wideEpochIdentity.value))
        #expect(!ExchangeIdentity.isCanonicalOpaqueIdentifierValue("v0:wide-epoch:01:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
        #expect(artifact.role == .sourceArtifact)
        expectInvalidProtocolDecimalSpellings()
    }

    private func expectInvalidProtocolDecimalSpellings() {
        #expect(throws: ExchangeIdentityError.invalidKeyEpoch("0")) {
            try KeyEpoch("0")
        }
    }

    @Test(
        "Nonnegative protocol decimals accept every canonical boundary spelling",
        arguments: ["0", "1", "18446744073709551616", "9999999999999999999999999999999999999999"]
    )
    func canonicalNonnegativeProtocolDecimal(_ rawValue: String) throws {
        #expect(try CanonicalNonnegativeDecimal(rawValue).rawValue == rawValue)
    }

    @Test(
        "Nonnegative protocol decimals reject every noncanonical spelling",
        arguments: ["", "00", "01", "-1", "+1", "1.0", " 1", "1 ", "١"]
    )
    func noncanonicalProtocolDecimal(_ rawValue: String) {
        #expect(throws: ExchangeIdentityError.invalidNonnegativeDecimal(rawValue)) {
            try CanonicalNonnegativeDecimal(rawValue)
        }
    }

    @Test(
        "Positive protocol decimals accept every canonical boundary spelling",
        arguments: ["1", "18446744073709551616", "9999999999999999999999999999999999999999"]
    )
    func canonicalPositiveProtocolDecimal(_ rawValue: String) throws {
        #expect(try KeyEpoch(rawValue).rawValue == rawValue)
    }

    @Test(
        "Positive protocol decimals reject zero and every noncanonical spelling",
        arguments: ["", "0", "00", "01", "-1", "+1", "1.0", " 1", "1 ", "١"]
    )
    func noncanonicalPositiveProtocolDecimal(_ rawValue: String) {
        #expect(throws: ExchangeIdentityError.invalidKeyEpoch(rawValue)) {
            try KeyEpoch(rawValue)
        }
    }
}

extension GroveFHIRExchangeIdentityTests {
    @Test("Identifier systems are absolute ASCII RFC 3986 URIs with complete escapes")
    func identifierSystemGrammar() throws {
        let valid = "urn:uuid:1f5c58aa-6ec6-4e79-a682-829a9debd3f5"
        let relative = "relative/path"
        let iri = "https://例.example/識別子"
        let malformedEscape = "https://example.org/%E8%AD%"
        let malformedAuthority = "https://exa[mple.org"
        let malformedIPLiteral = "https://[zz]/identifiers"
        let nonCanonicalQuery = "https://example.org/path?value=[]"
        #expect(try IdentifierSystem(valid).rawValue.hasPrefix("urn:"))
        #expect(IdentifierSystem("https://[2001:db8::1]/identifiers").rawValue.contains("[2001:db8::1]"))
        #expect(IdentifierSystem("urn://[v1.alpha:beta]/identifiers").rawValue.contains("[v1.alpha:beta]"))
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem(relative)) {
            try IdentifierSystem(relative)
        }
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem(iri)) {
            try IdentifierSystem(iri)
        }
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem(malformedEscape)) {
            try IdentifierSystem(malformedEscape)
        }
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem(malformedAuthority)) {
            try IdentifierSystem(malformedAuthority)
        }
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem(malformedIPLiteral)) {
            try IdentifierSystem(malformedIPLiteral)
        }
        #expect(throws: ExchangeIdentityError.nonCanonicalIdentifierSystem(
            supplied: nonCanonicalQuery,
            encoded: "https://example.org/path?value=%5B%5D"
        )) {
            try IdentifierSystem(nonCanonicalQuery)
        }
    }

    @Test("Stored JSON rejects an IRI before FHIRURI can normalize its identity system")
    func serializedIdentifierSystemIsValidatedBeforeDecoding() {
        let data = Data(#"""
        {
          "type": {
            "coding": [{
              "system": "https://grovealliance.org/fhir/mobile/CodeSystem/grove-identifier-role",
              "code": "record-version"
            }]
          },
          "system": "https://例.example/識別子",
          "value": "v0:test-key:1:xjbzwZqYyBE1boHxzOoS09iLXEMrvo0o8dpxtlwPQhE"
        }
        """#.utf8)
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem("https://例.example/識別子")) {
            try ExchangeIdentity.validateSerializedIdentifierSystems(in: data)
        }
    }

    @Test("A source-artifact retraction addresses the document's selected source-output key")
    func sourceArtifactRetractionUsesSelectedEntryKey() throws {
        let repository = try BusinessIdentifier(system: "https://study.example.org/repository", value: "primary")
        let record = try Self.scope.sourceRecord(
            adapterID: "healthkit",
            sourceType: "HKDataTypeIdentifierHeartbeatSeries",
            repositoryScope: repository,
            nativeRecordID: "recording-001"
        )
        let output = try record.output(role: "native-recording", discriminator: "single")
        let artifact = try record.artifact(formatCode: "beat-interval-series", partIndex: 0)
        let target = try RetractionRecord.Target(
            identifier: output,
            resourceType: .documentReference,
            role: .sourceArtifact
        )
        #expect(target.identifier == output)
        #expect(throws: RetractionRecord.Target.ValidationError.identifierRoleMismatch(
            targetRole: .sourceArtifact,
            identifierRole: .sourceArtifact
        )) {
            try RetractionRecord.Target(
                identifier: artifact,
                resourceType: .documentReference,
                role: .sourceArtifact
            )
        }
    }

    @Test("Splitting at an ASCII separator yields the Character split's fields, a colon joined by a combining mark included")
    func asciiSplitMatchesCharacterSplit() {
        let values = [
            "v0:role:1:digest", "v0::1:", ":", "", "::a::", "a:b:c:d:e", "v0:r\u{301}ole:1:x", "v0:\u{301}x:y",
            "\u{E9}:\u{FC}", "a\r\n:b", "\u{1F600}:x"
        ]
        for value in values {
            for omitting in [true, false] {
                for maxSplits in [2, Int.max] {
                    #expect(
                        value.split(ascii: 0x3A, maxSplits: maxSplits, omittingEmptySubsequences: omitting)
                            == value.split(separator: ":", maxSplits: maxSplits, omittingEmptySubsequences: omitting),
                        "\(value.debugDescription), maxSplits \(maxSplits), omitting \(omitting)"
                    )
                }
            }
        }
    }
}

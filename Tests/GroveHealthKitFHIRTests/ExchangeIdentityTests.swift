//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import ModelsR4
import Testing

@Suite
struct GroveFHIRExchangeIdentityTests {
    private static var scope: PseudonymousIdentityScope {
        get throws {
            try PseudonymousIdentityScope.conformanceTesting(
                systems: PseudonymousIdentitySystems(
                    sourceRecord: "https://study.example.org/fhir/NamingSystem/source-record-test-key-1",
                    sourceOutput: "https://study.example.org/fhir/NamingSystem/source-output-test-key-1",
                    writerRecord: "https://study.example.org/fhir/NamingSystem/writer-record-test-key-1",
                    providerRecord: "https://study.example.org/fhir/NamingSystem/provider-record-test-key-1",
                    providerOutput: "https://study.example.org/fhir/NamingSystem/provider-output-test-key-1",
                    sourceArtifact: "https://study.example.org/fhir/NamingSystem/source-artifact-test-key-1",
                    providerArtifact: "https://study.example.org/fhir/NamingSystem/provider-artifact-test-key-1",
                    sourceContext: "https://study.example.org/fhir/NamingSystem/source-context-test-key-1",
                    recordingDevice: "https://study.example.org/fhir/NamingSystem/recording-device-test-key-1",
                    deviceSnapshot: "https://study.example.org/fhir/NamingSystem/device-snapshot-test-key-1"
                ),
                keyID: "test-key",
                epoch: 1
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
        #expect(identifier.value == "v2:test-key:1:nq3ZogmXHSznC1LC1wNMm7KTQChgapPzmjmGeB9RHcw")
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
        )
        #expect(identifier.value == "v2:test-key:1:UKY2qgzSB8--SueGxEfOhpElzHTVJ6usIUWV_KUTD6o")
        #expect(identifier.role == .sourceRecord)
    }

    @Test("A source-output HMAC has exactly one role and one discriminator frame")
    func sourceOutputVector() throws {
        let identifier = try Self.scope.sourceOutput(
            adapterID: "health-connect",
            sourceType: "HeartRateRecord",
            repositoryScope: BusinessIdentifier(
                system: "urn:uuid:1f5c58aa-6ec6-4e79-a682-829a9debd3f5",
                value: "default"
            ),
            nativeRecordID: "record-heart-001",
            outputRole: "sample",
            outputDiscriminator: "2026-08-19T10:30:00.000000000Z|0"
        )
        #expect(identifier.value == "v2:test-key:1:PQCWz9dZSrJm-KrbhbkckGeowkjhSSwWDRCVuF3VfXw")
        #expect(identifier.role == .sourceOutput)
    }

    @Test("Matches complete-pair provider, writer, and recording-device vectors")
    func completePairVectors() throws {
        let provider = try Self.scope.providerRecord(
            providerCode: .withings,
            sourceType: "measure",
            providerScope: Self.identifier("https://accounts.example.org", "patient|α"),
            nativeRecordID: "17348211"
        )
        let providerOutput = try Self.scope.providerOutput(
            providerCode: .withings,
            sourceType: "getmeas:9+10",
            providerScope: Self.identifier("https://accounts.example.org", "patient|α"),
            nativeRecordID: "17348211",
            outputRole: "blood-pressure-panel",
            outputDiscriminator: "single"
        )
        let providerArtifact = try Self.scope.providerArtifact(
            providerCode: .googleHealthAPI,
            sourceType: "heart-rate",
            providerScope: Self.identifier("https://accounts.example.org", "patient|α"),
            nativeRecordID: "recording-001",
            formatCode: "provider-recording",
            partIndex: 0
        )
        let writer = try Self.scope.writerRecord(
            writerApplication: Self.identifier("https://applications.example.org", "com.withings.wiscale2"),
            writerRecordID: "logical-record-001"
        )
        let recordingDevice = try Self.scope.recordingDevice(
            adapterID: "healthkit",
            subject: Self.identifier("https://study.example.org/participants", "participant-001"),
            stableUnitToken: "watch-unit-token-001"
        )
        #expect(provider.value == "v2:test-key:1:p3NFdQ-hmHon98JG7cmCbLncbAmNkjkBa5sYocSr6pw")
        #expect(providerOutput.value == "v2:test-key:1:HjBwHRt0W3-CbhJbc7hGpWRp92zug70gt5m626T4Y2U")
        #expect(providerArtifact.value == "v2:test-key:1:CxLpZ4NQee12xCyJCGimrxMLEKvbRt54Kl6RTh9UsrU")
        #expect(writer.value == "v2:test-key:1:N4QSlWU6sNp9ahfyfSRTUO0K_VIZZoy-Lw3JTNrDzP4")
        #expect(recordingDevice.value == "v2:test-key:1:MWGV3Vfk0jfLIr0nowr_I7TAwoqGtpSkxUi1d8FxTnE")
    }

    @Test("Matches normative event, entry-node, and UUIDv5 vectors")
    func graphKeyVectors() throws {
        let event = try ExchangeEventIdentifier(
            system: "https://study.example.org/fhir/NamingSystem/grove-event-v2",
            producerInstance: #require(UUID(uuidString: "1f5c58aa-6ec6-4e79-a682-829a9debd3f5")),
            sequence: 42
        )
        let node = try ExchangeNodeKey(
            system: "https://study.example.org/fhir/NamingSystem/grove-entry-node-v2",
            eventIdentifier: event,
            nodeRole: "conversion-provenance",
            ordinal: 0
        )
        let unicode = try BusinessIdentifier(
            system: "https://xn--fsq.example/%E8%AD%98%E5%88%A5%E5%AD%90",
            value: "café|東京"
        )
        #expect(event.businessIdentifier.value == "e2:1f5c58aa-6ec6-4e79-a682-829a9debd3f5:42")
        #expect(node.identifier.value == "n2:conversion-provenance:0:SwGD7C4DT5_9kgIOQ9h7W8I4UdwJPuEOnkh2TgQVwko")
        #expect(try ExchangeIdentity.fullURL(for: node.identifier) == "urn:uuid:9908feb7-0370-5f06-a689-f8afa210eb41")
        #expect(try ExchangeIdentity.fullURL(for: unicode) == "urn:uuid:d35e4203-71f6-595c-bd1b-306b8414974e")
    }

    @Test("Typed event construction rejects UUIDs outside the canonical RFC 4122 domain")
    func rejectsInvalidProducerInstance() throws {
        let invalid = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(throws: ExchangeIdentityError.invalidProducerInstance(invalid)) {
            try ExchangeEventIdentifier(
                system: "https://study.example.org/fhir/NamingSystem/grove-event-v2",
                producerInstance: invalid,
                sequence: 1
            )
        }
    }

    @Test("A Grove identifier-role coding without a code fails closed")
    func rejectsMissingIdentifierRoleCode() {
        let identifier = Identifier(
            system: "https://study.example.org/fhir/NamingSystem/source-record-test-key-1",
            type: CodeableConcept(coding: [Coding(system: Canonicals.identifierRoleCodeSystem)]),
            value: "v2:test-key:1:UKY2qgzSB8--SueGxEfOhpElzHTVJ6usIUWV_KUTD6o"
        )
        #expect(throws: ExchangeIdentityError.invalidIdentifierRole("missing")) {
            try BusinessIdentifier(identifier)
        }
    }

    @Test("Length framing distinguishes delimiter and field-boundary collisions")
    func lengthFramingIsUnambiguous() throws {
        #expect(try LengthFramedUTF8.encode(["a|b", "c"]) != LengthFramedUTF8.encode(["a", "b|c"]))
        #expect(try LengthFramedUTF8.encode(["é"]) != LengthFramedUTF8.encode(["e", "\u{301}"]))
        #expect(try LengthFramedUTF8.encode([""]) == Data([0, 0, 0, 0]))
    }

    @Test("The published conformance key cannot initialize a production identity scope")
    func rejectsPublishedConformanceKeyInProductionInitializer() throws {
        #expect(throws: PseudonymousIdentityError.publishedConformanceKeyProhibited) {
            try PseudonymousIdentityScope(
                systems: Self.scope.systems,
                keyID: "must-not-ship",
                epoch: 1,
                key: Data((0...31).map(UInt8.init))
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
        let event = try ExchangeEventIdentifier(
            system: "https://example.org/events",
            producerInstance: #require(UUID(uuidString: "2eafba7b-4c21-4bf5-ad46-351b0176b25a")),
            sequence: 1
        )
        expectEmptySourceComponents(repository: repository)
        #expect(Set(GroveProviderCode.allCases.map(\.rawValue)) == ["google-health-api", "oura", "withings"])
        for providerCode in GroveProviderCode.allCases.map(\.rawValue) {
            expectProviderKindRequired(providerCode, repository: repository)
        }
        expectEmptyDerivedComponents(
            repository: repository,
            application: application,
            subject: subject,
            event: event
        )
        // The protocol requires nonempty Unicode strings, not a global whitespace normalization.
        #expect(try Self.scope.sourceRecord(
            adapterID: "adapter",
            sourceType: "type",
            repositoryScope: repository,
            nativeRecordID: " "
        ).role == .sourceRecord)
    }

    private func expectEmptySourceComponents(repository: BusinessIdentifier) {
        #expect(throws: PseudonymousIdentityError.emptyComponent("adapterID")) {
            try Self.scope.sourceRecord(adapterID: "", sourceType: "type", repositoryScope: repository, nativeRecordID: "id")
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("sourceType")) {
            try Self.scope.sourceRecord(adapterID: "adapter", sourceType: "", repositoryScope: repository, nativeRecordID: "id")
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("nativeRecordID")) {
            try Self.scope.sourceRecord(adapterID: "adapter", sourceType: "type", repositoryScope: repository, nativeRecordID: "")
        }
    }

    private func expectEmptyDerivedComponents(
        repository: BusinessIdentifier,
        application: BusinessIdentifier,
        subject: BusinessIdentifier,
        event: ExchangeEventIdentifier
    ) {
        #expect(throws: PseudonymousIdentityError.emptyComponent("outputRole")) {
            try Self.scope.sourceOutput(
                adapterID: "adapter",
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id",
                outputRole: "",
                outputDiscriminator: "single"
            )
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("outputDiscriminator")) {
            try Self.scope.sourceOutput(
                adapterID: "adapter",
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id",
                outputRole: "primary",
                outputDiscriminator: ""
            )
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("writerRecordID")) {
            try Self.scope.writerRecord(writerApplication: application, writerRecordID: "")
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("formatCode")) {
            try Self.scope.sourceArtifact(
                adapterID: "adapter",
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id",
                formatCode: "",
                partIndex: 0
            )
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("contextType")) {
            try Self.scope.sourceContext(
                adapterID: "adapter", contextType: "", repositoryScope: repository, nativeContextID: "id"
            )
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("nativeContextID")) {
            try Self.scope.sourceContext(
                adapterID: "adapter", contextType: "context", repositoryScope: repository, nativeContextID: ""
            )
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("stableUnitToken")) {
            try Self.scope.recordingDevice(adapterID: "adapter", subject: subject, stableUnitToken: "")
        }
        #expect(throws: PseudonymousIdentityError.emptyComponent("sourceDeviceToken")) {
            try Self.scope.deviceSnapshot(eventIdentifier: event, deviceRole: .host, sourceDeviceToken: "")
        }
    }

    private func expectProviderKindRequired(_ providerCode: String, repository: BusinessIdentifier) {
        #expect(throws: PseudonymousIdentityError.providerKindRequired(providerCode)) {
            try Self.scope.sourceRecord(
                adapterID: providerCode,
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id"
            )
        }
        #expect(throws: PseudonymousIdentityError.providerKindRequired(providerCode)) {
            try Self.scope.sourceOutput(
                adapterID: providerCode,
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id",
                outputRole: "primary",
                outputDiscriminator: "single"
            )
        }
        #expect(throws: PseudonymousIdentityError.providerKindRequired(providerCode)) {
            try Self.scope.sourceArtifact(
                adapterID: providerCode,
                sourceType: "type",
                repositoryScope: repository,
                nativeRecordID: "id",
                formatCode: "native",
                partIndex: 0
            )
        }
    }

    @Test("The closed identity-kind domain publishes the protocol's exact arities")
    func identityKindArities() {
        #expect(Dictionary(uniqueKeysWithValues: PseudonymousIdentityKind.allCases.map {
            ($0.rawValue, $0.componentCount)
        }) == [
            "source-record": 5,
            "source-output": 7,
            "writer-record": 3,
            "provider-record": 5,
            "provider-output": 7,
            "source-artifact": 7,
            "provider-artifact": 7,
            "source-context": 5,
            "recording-device": 4,
            "device-snapshot": 4
        ])
    }

    @Test("Protocol decimal coordinates have canonical spelling and no UInt64 ceiling")
    func unboundedProtocolDecimals() throws {
        let aboveUInt64 = "18446744073709551616"
        let wideEpochScope = try PseudonymousIdentityScope(
            systems: Self.scope.systems,
            keyID: "wide-epoch",
            epoch: CanonicalPositiveDecimal(aboveUInt64),
            key: Data(repeating: 0x43, count: 32)
        )
        let wideEpochIdentity = try wideEpochScope.sourceRecord(
            adapterID: "healthkit",
            sourceType: "HKQuantityTypeIdentifierHeartRate",
            repositoryScope: BusinessIdentifier(system: "https://store.example.org", value: "default"),
            nativeRecordID: "record-001"
        )
        let event = try ExchangeEventIdentifier(
            system: "https://study.example.org/fhir/NamingSystem/grove-event-v2",
            producerInstance: #require(UUID(uuidString: "1f5c58aa-6ec6-4e79-a682-829a9debd3f5")),
            sequence: CanonicalPositiveDecimal(aboveUInt64)
        )
        let node = try ExchangeNodeKey(
            system: "https://study.example.org/fhir/NamingSystem/grove-entry-node-v2",
            eventIdentifier: event,
            nodeRole: "conversion-provenance",
            ordinal: CanonicalNonnegativeDecimal(aboveUInt64)
        )
        let artifact = try Self.scope.sourceArtifact(
            adapterID: "sensorkit",
            sourceType: "device-usage",
            repositoryScope: BusinessIdentifier(system: "https://store.example.org", value: "default"),
            nativeRecordID: "record-001",
            formatCode: "native-recording",
            partIndex: CanonicalNonnegativeDecimal(aboveUInt64)
        )
        #expect(event.sequence.rawValue == aboveUInt64)
        #expect(wideEpochScope.epoch.rawValue == aboveUInt64)
        #expect(wideEpochIdentity.value.hasPrefix("v2:wide-epoch:\(aboveUInt64):"))
        #expect(ExchangeIdentity.isCanonicalOpaqueIdentifierValue(wideEpochIdentity.value))
        #expect(!ExchangeIdentity.isCanonicalOpaqueIdentifierValue("v2:wide-epoch:01:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
        #expect(event.businessIdentifier.value.hasSuffix(":\(aboveUInt64)"))
        #expect(node.ordinal.rawValue == aboveUInt64)
        #expect(node.identifier.value.contains(":\(aboveUInt64):"))
        #expect(artifact.role == .sourceArtifact)
        expectInvalidProtocolDecimalSpellings()
    }

    private func expectInvalidProtocolDecimalSpellings() {
        #expect(throws: CanonicalDecimalError.invalidPositiveDecimal("0")) {
            try CanonicalPositiveDecimal("0")
        }
        #expect(throws: ExchangeIdentityError.invalidEventIdentifier(
            "e2:1f5c58aa-6ec6-4e79-a682-829a9debd3f5:01"
        )) {
            try ExchangeEventIdentifier(BusinessIdentifier(
                system: "https://study.example.org/fhir/NamingSystem/grove-event-v2",
                value: "e2:1f5c58aa-6ec6-4e79-a682-829a9debd3f5:01",
                role: .event
            ))
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
        #expect(throws: CanonicalDecimalError.invalidNonnegativeDecimal(rawValue)) {
            try CanonicalNonnegativeDecimal(rawValue)
        }
    }

    @Test(
        "Positive protocol decimals accept every canonical boundary spelling",
        arguments: ["1", "18446744073709551616", "9999999999999999999999999999999999999999"]
    )
    func canonicalPositiveProtocolDecimal(_ rawValue: String) throws {
        #expect(try CanonicalPositiveDecimal(rawValue).rawValue == rawValue)
    }

    @Test(
        "Positive protocol decimals reject zero and every noncanonical spelling",
        arguments: ["", "0", "00", "01", "-1", "+1", "1.0", " 1", "1 ", "١"]
    )
    func noncanonicalPositiveProtocolDecimal(_ rawValue: String) {
        #expect(throws: CanonicalDecimalError.invalidPositiveDecimal(rawValue)) {
            try CanonicalPositiveDecimal(rawValue)
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
              "code": "event"
            }]
          },
          "system": "https://例.example/識別子",
          "value": "e2:1f5c58aa-6ec6-4e79-a682-829a9debd3f5:42"
        }
        """#.utf8)
        #expect(throws: ExchangeIdentityError.invalidIdentifierSystem("https://例.example/識別子")) {
            try ExchangeIdentity.validateSerializedIdentifierSystems(in: data)
        }
    }

    @Test("A source-artifact retraction addresses the document's selected source-output key")
    func sourceArtifactRetractionUsesSelectedEntryKey() throws {
        let repository = try BusinessIdentifier(system: "https://study.example.org/repository", value: "primary")
        let output = try Self.scope.sourceOutput(
            adapterID: "healthkit",
            sourceType: "HKDataTypeIdentifierHeartbeatSeries",
            repositoryScope: repository,
            nativeRecordID: "recording-001",
            outputRole: "native-recording",
            outputDiscriminator: "single"
        )
        let artifact = try Self.scope.sourceArtifact(
            adapterID: "healthkit",
            sourceType: "HKDataTypeIdentifierHeartbeatSeries",
            repositoryScope: repository,
            nativeRecordID: "recording-001",
            formatCode: "beat-interval-series",
            partIndex: 0
        )
        let target = try RetractionTarget(
            identifier: output,
            resourceType: .documentReference,
            role: .sourceArtifact
        )
        #expect(target.identifier == output)
        #expect(throws: RetractionTargetError.identifierRoleMismatch(
            targetRole: .sourceArtifact,
            identifierRole: .sourceArtifact
        )) {
            try RetractionTarget(
                identifier: artifact,
                resourceType: .documentReference,
                role: .sourceArtifact
            )
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
import ModelsR4


/// Records assembled under the published test key, for the suites of the assembler and the packer.
enum ExchangeRecordFixtures {
    static let instant = Date(timeIntervalSince1970: 1_787_931_125)

    static let adapter = ExchangeAdapterContract(
        adapterID: "test-adapter",
        provenanceProfile: Profile.groveMobileConversionProvenance,
        applicationDeviceProfile: Profile.groveApplicationDevice
    )

    static var identityScope: OpaqueIdentityScope {
        get throws {
            let epoch = try KeyEpoch("1")
            let systems = try DeploymentIdentifierSystems.derived(
                root: IdentifierSystem("https://study.example.org/fhir"),
                keyID: "test-key",
                epoch: epoch
            )
            return try .conformanceTesting(systems: systems, keyID: "test-key", epoch: epoch)
        }
    }

    static func subject(_ value: String = "participant-001") throws -> Subject {
        .logical(try BusinessIdentifier(system: IdentifierSystem("https://study.example.org/fhir/identifiers/participant"), value: value))
    }

    static func enrollment(protocolVersion: String = "1.0", enrollment: String = "enrollment-1") throws -> StudyEnrollment {
        try StudyEnrollment(
            study: BusinessIdentifier(system: IdentifierSystem("https://study.example.org/fhir/identifiers/study"), value: "study-1"),
            protocolURL: "https://study.example.org/fhir/PlanDefinition/protocol",
            protocolVersion: protocolVersion,
            enrollment: BusinessIdentifier(system: IdentifierSystem("https://study.example.org/fhir/identifiers/enrollment"), value: enrollment)
        )
    }

    static func assembler(
        subject: Subject? = nil,
        studies: [StudyEnrollment] = [],
        operatingSystemVersion: String = "26.0.0"
    ) throws -> ExchangeGraphAssembler {
        let scope = ExchangeEnvelope.Scope(
            adapter: adapter,
            identityScope: try identityScope,
            subject: try subject ?? Self.subject(),
            repositoryScope: try BusinessIdentifier(system: IdentifierSystem("https://study.example.org/fhir/identifiers/repository"), value: "primary")
        )
        let facts = ConversionFacts(
            application: try ApplicationDevice(name: "Study", bundleIdentifier: "org.example.study", version: "1.0", build: "42"),
            host: try HostDevice(
                operatingSystemName: "iOS",
                operatingSystemVersion: operatingSystemVersion,
                operatingSystemBuild: "23A341",
                productType: "iPhone17,1",
                model: "iPhone",
                name: "iPhone",
                manufacturer: "Apple"
            ),
            studies: studies
        )
        return ExchangeGraphAssembler(envelope: ExchangeEnvelope(scope: scope, facts: facts))
    }

    /// A heart rate of `value`, the record's one output.
    static func draft(
        nativeRecordID: String = "record-1",
        value: Decimal = 72,
        recordingDevice: RecordingDevice? = nil,
        at instant: Date = instant,
        assembler: ExchangeGraphAssembler
    ) throws -> ExchangeRecordDraft {
        var observation = Observation(
            code: CodeableConcept(coding: [Coding(code: "8867-4", display: "Heart rate", system: "http://loinc.org")]),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: [Profile.groveMobileHeartRate])
        observation.effective = .dateTime(FHIRPrimitive(try DateTime("2026-08-20T08:30:00Z")))
        observation.value = .quantity(Quantity(
            code: "/min",
            system: Canonicals.ucum,
            unit: "beats/minute",
            value: FHIRPrimitive(FHIRDecimal(value))
        ))
        return ExchangeRecordDraft(
            instant: instant,
            sourceRecord: try assembler.envelope.scope.sourceRecord(sourceType: "heart-rate", nativeRecordID: nativeRecordID),
            outputs: [ExchangeOutputDraft(role: "primary", resource: .observation(observation))],
            recordingDevice: recordingDevice
        )
    }

    static func record(
        nativeRecordID: String = "record-1",
        value: Decimal = 72,
        recordingDevice: RecordingDevice? = nil,
        at instant: Date = instant,
        assembler: ExchangeGraphAssembler? = nil
    ) throws -> ExchangeRecord {
        let assembler = try assembler ?? Self.assembler()
        return try assembler.assemble(
            draft(nativeRecordID: nativeRecordID, value: value, recordingDevice: recordingDevice, at: instant, assembler: assembler)
        ).record
    }

    static func retraction(
        nativeRecordID: String = "record-1",
        occurred: RetractionRecord.Occurrence = .instant(instant),
        at instant: Date = instant,
        assembler: ExchangeGraphAssembler? = nil
    ) throws -> ExchangeRecord {
        let assembler = try assembler ?? Self.assembler()
        let sourceRecord = try assembler.envelope.scope.sourceRecord(sourceType: "heart-rate", nativeRecordID: nativeRecordID)
        return try assembler.retraction(
            of: sourceRecord.identifier,
            targets: [RetractionRecord.Target(sourceRecord: sourceRecord.identifier)],
            occurred: occurred,
            at: instant
        ).record
    }

    /// The resources of a record's Bundle, as its JSON states them.
    static func resources(of record: ExchangeRecord) throws -> [[String: Any]] {
        let root = try JSONSerialization.jsonObject(with: record.json) as? [String: Any]
        return (root?["entry"] as? [[String: Any]] ?? []).compactMap { $0["resource"] as? [String: Any] }
    }

    /// `record`'s JSON with `transform` applied to its one resource of `resourceType`.
    static func json(
        of record: ExchangeRecord,
        changing resourceType: String,
        _ transform: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try JSONSerialization.jsonObject(with: record.json) as? [String: Any] ?? [:]
        var entries = root["entry"] as? [[String: Any]] ?? []
        for index in entries.indices {
            guard var resource = entries[index]["resource"] as? [String: Any], resource["resourceType"] as? String == resourceType else {
                continue
            }
            transform(&resource)
            entries[index]["resource"] = resource
        }
        root["entry"] = entries
        return try JSONSerialization.data(withJSONObject: root)
    }
}

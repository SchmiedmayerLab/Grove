//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract
@testable import GroveQuestionnaireExtraction
import ModelsR4
import Testing


/// The deployment of the questionnaire guide's worked example, and an exporter over it.
enum QuestionnaireExportFixtures {
    /// The guide's conversion instant, 2026-08-28T15:32:05Z.
    static let instant = Date(timeIntervalSince1970: 1_787_931_125)

    /// The guide's deployment, under the published test key.
    static var identityScope: OpaqueIdentityScope {
        get throws {
            let epoch = KeyEpoch(1)
            return try OpaqueIdentityScope.conformanceTesting(
                systems: DeploymentIdentifierSystems.derived(root: "https://study.example.org/fhir", keyID: "test-key", epoch: epoch),
                keyID: "test-key",
                epoch: epoch
            )
        }
    }

    static var repositoryScope: BusinessIdentifier {
        get throws {
            try BusinessIdentifier(
                system: IdentifierSystem("https://study.example.org/fhir/NamingSystem/questionnaire-response"),
                value: "default"
            )
        }
    }

    static var pseudonym: BusinessIdentifier {
        get throws {
            try BusinessIdentifier(system: "https://example.org/research/participant-id", value: "participant-001")
        }
    }

    /// The guide's Patient, which states the pseudonym.
    static var patient: ModelsR4.Patient {
        get throws {
            var patient = ModelsR4.Patient()
            patient.id = "GroveQuestionnairePatientExample"
            patient.identifier = [try pseudonym.fhirIdentifier]
            return patient
        }
    }

    static func fixture<Resource: Decodable>(_ name: String, as type: Resource.Type) throws -> Resource {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(Resource.self, from: Data(contentsOf: url))
    }

    /// The guide's Home Vitals pair, with its response changed by `change`.
    static func guideRecord(
        changing change: (inout ModelsR4.QuestionnaireResponse) throws -> Void = { _ in }
    ) throws -> QuestionnaireFHIRExporter.Record {
        var response = try fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        try change(&response)
        return QuestionnaireFHIRExporter.Record(
            questionnaire: try fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
            response: response
        )
    }

    /// A writer context of the guide's client, at a release other than the guide's.
    static func writer(
        build: String? = nil,
        hostModel: String? = nil,
        hostOperatingSystemName: String? = nil,
        hostOperatingSystemVersion: String? = nil,
        hostOperatingSystemBuild: String? = nil
    ) throws -> QuestionnaireWriterContext {
        try QuestionnaireWriterContext(
            applicationIdentifier: BusinessIdentifier(
                system: "https://study.example.org/fhir/NamingSystem/application",
                value: "org.grovealliance.example.client"
            ),
            applicationName: "Grove Questionnaire Client",
            applicationVersion: "1.5.0",
            applicationBuild: build,
            hostModel: hostModel,
            hostOperatingSystemName: hostOperatingSystemName,
            hostOperatingSystemVersion: hostOperatingSystemVersion,
            hostOperatingSystemBuild: hostOperatingSystemBuild
        )
    }

    /// A producer, by default with the guide's Patient as its bundled subject.
    static func producer(subject: Subject? = nil, studies: [StudyEnrollment] = []) throws -> ExchangeProducer {
        try ExchangeProducer(
            identityScope: identityScope,
            subject: subject ?? .bundled(pseudonym, patient),
            application: ApplicationDevice(name: "Grove Example App", bundleIdentifier: "org.grovealliance.example.app", version: "2.0.0"),
            host: HostDevice(operatingSystemVersion: "26.0", productType: "iPhone17,1"),
            studies: studies
        )
    }

    static func exporter(_ producer: ExchangeProducer) throws -> QuestionnaireFHIRExporter {
        QuestionnaireFHIRExporter(producer: producer, repositoryScope: try repositoryScope)
    }

    /// Every export of one call, in delivery order.
    static func collect(
        _ exporter: QuestionnaireFHIRExporter,
        _ records: [QuestionnaireFHIRExporter.Record],
        at instant: Date = instant
    ) async throws -> [QuestionnaireFHIRExporter.Export] {
        var exports: [QuestionnaireFHIRExporter.Export] = []
        try await exporter.export(records, at: instant) { exports.append($0) }
        return exports
    }

    /// The record of `record`, exported by a fresh producer at the guide's instant.
    static func exported(_ record: QuestionnaireFHIRExporter.Record) async throws -> ExchangeRecord {
        try #require(try await collect(exporter(producer()), [record]).first?.record)
    }

    static func study(_ id: String) throws -> StudyEnrollment {
        try StudyEnrollment(
            study: BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/research-study", value: id),
            protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/\(id)")),
            protocolVersion: "1",
            enrollment: BusinessIdentifier(system: "https://study.example.org/fhir/NamingSystem/research-subject", value: "enrollment-\(id)")
        )
    }
}


extension ExchangeRecord {
    /// The one-record Bundle ``json`` states.
    var bundle: ModelsR4.Bundle {
        get throws {
            try JSONDecoder().decode(ModelsR4.Bundle.self, from: json)
        }
    }

    var resourceTypes: [String] {
        get throws {
            try bundle.entry?.compactMap { $0.resource?.resourceType } ?? []
        }
    }

    var observations: [Observation] {
        get throws {
            try bundle.entry?.compactMap { $0.resource?.get(if: Observation.self) } ?? []
        }
    }

    var devices: [Device] {
        get throws {
            try bundle.entry?.compactMap { $0.resource?.get(if: Device.self) } ?? []
        }
    }

    var provenance: Provenance {
        get throws {
            try #require(try bundle.entry?.lazy.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        }
    }

    /// The one QuestionnaireResponse entry the record carries.
    var responseEntry: BundleEntry {
        get throws {
            try #require(try bundle.entry?.first { $0.resource?.get(if: ModelsR4.QuestionnaireResponse.self) != nil })
        }
    }

    var response: ModelsR4.QuestionnaireResponse {
        get throws {
            try #require(try responseEntry.resource?.get(if: ModelsR4.QuestionnaireResponse.self))
        }
    }
}


extension Device {
    /// Every `Device.version` value, by its type coding's code.
    var statedVersions: [String: String] {
        Dictionary(uniqueKeysWithValues: (version ?? []).compactMap { version in
            guard let code = version.type?.coding?.first?.code?.value?.string, let value = version.value.value?.string else {
                return nil
            }
            return (code, value)
        })
    }
}

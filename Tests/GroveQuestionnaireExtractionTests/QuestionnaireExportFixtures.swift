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
    /// The producer instance of the guide's event `e0:6f9d1c4a-2b7e-4f18-9c33-5a1d0e7b2c48:1`.
    static let producerInstance = UUID(uuid: (
        0x6f, 0x9d, 0x1c, 0x4a, 0x2b, 0x7e, 0x4f, 0x18,
        0x9c, 0x33, 0x5a, 0x1d, 0x0e, 0x7b, 0x2c, 0x48
    ))
    /// The guide's conversion instant, 2026-08-28T15:32:05Z.
    static let instant = Date(timeIntervalSince1970: 1_787_931_125)

    static var identityScope: OpaqueIdentityScope {
        get throws {
            let systems = DeploymentIdentifierSystems(
                sourceRecord: "https://study.example.org/fhir/NamingSystem/grove-source-record-v0",
                sourceOutput: "https://study.example.org/fhir/NamingSystem/grove-source-output-v0",
                writerRecord: "https://study.example.org/fhir/NamingSystem/grove-writer-record-v0",
                providerRecord: "https://study.example.org/fhir/NamingSystem/grove-provider-record-v0",
                providerOutput: "https://study.example.org/fhir/NamingSystem/grove-provider-output-v0",
                sourceArtifact: "https://study.example.org/fhir/NamingSystem/grove-source-artifact-v0",
                providerArtifact: "https://study.example.org/fhir/NamingSystem/grove-provider-artifact-v0",
                sourceContext: "https://study.example.org/fhir/NamingSystem/grove-source-context-v0",
                recordingDevice: "https://study.example.org/fhir/NamingSystem/grove-recording-device-v0",
                deviceSnapshot: "https://study.example.org/fhir/NamingSystem/grove-device-snapshot-v0",
                event: "https://study.example.org/fhir/NamingSystem/grove-event-v0",
                entryNode: "https://study.example.org/fhir/NamingSystem/grove-entry-node-v0"
            )
            return try OpaqueIdentityScope.conformanceTesting(systems: systems, keyID: "test-key", epoch: EventSequence(1))
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
    static func writer(build: String?, host: (model: String, operatingSystemVersion: String)?) throws -> QuestionnaireWriterContext {
        try QuestionnaireWriterContext(
            applicationIdentifier: BusinessIdentifier(
                system: "https://study.example.org/fhir/NamingSystem/application",
                value: "org.grovealliance.example.client"
            ),
            applicationName: "Grove Questionnaire Client",
            applicationVersion: "1.5.0",
            applicationBuild: build,
            hostModel: host?.model,
            hostOperatingSystemVersion: host?.operatingSystemVersion
        )
    }

    /// A producer over `storage`, by default with the guide's Patient as its bundled subject.
    ///
    /// A fresh ledger mints its own producer instance, as every installation's does. Pass `pinning` to number from
    /// the guide's event instead; the process tracks holds by producer instance, so only tests that release nothing
    /// may share one instance across ledgers.
    static func producer(
        subject: Subject? = nil,
        studies: [StudyEnrollment] = [],
        pinning instance: UUID? = nil,
        storage: ExchangeProducer.InMemoryStorage = ExchangeProducer.InMemoryStorage()
    ) throws -> ExchangeProducer {
        if let instance {
            try storage.transaction { transaction in
                if try transaction.read(LedgerKey.producer) == nil {
                    try transaction.write(ProducerEntry(instance: instance, next: 1).encoded(), for: LedgerKey.producer)
                }
            }
        }
        return try ExchangeProducer(
            identityScope: identityScope,
            subject: subject ?? .bundled(pseudonym, patient),
            application: ApplicationDevice(name: "Grove Example App", bundleIdentifier: "org.grovealliance.example.app", version: "2.0.0"),
            host: HostDevice(operatingSystemVersion: "26.0", modelNumber: "iPhone17,1"),
            studies: studies,
            storage: storage
        )
    }

    static func exporter(_ producer: ExchangeProducer) throws -> QuestionnaireFHIRExporter {
        QuestionnaireFHIRExporter(producer: producer, repositoryScope: try repositoryScope)
    }

    /// Every export of one call, in delivery order, and the call's receipt.
    static func collect(
        _ exporter: QuestionnaireFHIRExporter,
        _ records: [QuestionnaireFHIRExporter.Record],
        at instant: Date = instant
    ) throws -> (exports: [QuestionnaireFHIRExporter.Export], receipt: ExchangeProducer.Receipt) {
        var exports: [QuestionnaireFHIRExporter.Export] = []
        let receipt = try exporter.export(records, at: instant) { exports.append($0) }
        return (exports, receipt)
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


extension ExchangeGraph {
    var resourceTypes: [String] {
        bundle.entry?.compactMap { $0.resource?.resourceType } ?? []
    }

    var observations: [Observation] {
        bundle.entry?.compactMap { entry in
            if case .observation(let observation)? = entry.resource { observation } else { nil }
        } ?? []
    }
}

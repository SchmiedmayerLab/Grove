//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
@testable import GroveQuestionnaireExtraction
import ModelsR4
import Testing


/// Projects the implementation guide's Home Vitals pair and holds the result to the contract.
///
/// The pair is vendored byte-for-byte from `grove-fhir` (`questionnaire/fixtures/extraction`),
/// so what these tests exercise is exactly what the guide documents.
/// Decoders for the guide's committed bundle, kept flat and minimal.
private struct GoldenIdentifier: Decodable {
    let system: String
    let value: String
}

private struct GoldenEntryExt: Decodable {
    let valueIdentifier: GoldenIdentifier
}

private struct GoldenEntry: Decodable {
    let fullUrl: String
    let `extension`: [GoldenEntryExt]
}

private struct GoldenBundle: Decodable {
    let identifier: GoldenIdentifier
    let timestamp: String
    let entry: [GoldenEntry]
}


@Suite("Questionnaire Observation Extraction")
struct ObservationExtractionTests {
    // MARK: Fixtures

    private static func fixture<Resource: Decodable>(_ name: String, as type: Resource.Type) throws -> Resource {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json"
        ))
        return try JSONDecoder().decode(Resource.self, from: Data(contentsOf: url))
    }

    private static func context() throws -> QuestionnaireExtractionContext {
        let systems = try PseudonymousIdentitySystems(
            sourceRecord: "https://study.example.org/fhir/NamingSystem/grove-source-record-v0",
            sourceOutput: "https://study.example.org/fhir/NamingSystem/grove-source-output-v0",
            writerRecord: "https://study.example.org/fhir/NamingSystem/grove-writer-record-v0",
            providerRecord: "https://study.example.org/fhir/NamingSystem/grove-provider-record-v0",
            providerOutput: "https://study.example.org/fhir/NamingSystem/grove-provider-output-v0",
            sourceArtifact: "https://study.example.org/fhir/NamingSystem/grove-source-artifact-v0",
            providerArtifact: "https://study.example.org/fhir/NamingSystem/grove-provider-artifact-v0",
            sourceContext: "https://study.example.org/fhir/NamingSystem/grove-source-context-v0",
            recordingDevice: "https://study.example.org/fhir/NamingSystem/grove-recording-device-v0",
            deviceSnapshot: "https://study.example.org/fhir/NamingSystem/grove-device-snapshot-v0"
        )
        let scope = try PseudonymousIdentityScope.conformanceTesting(
            systems: systems,
            keyID: "test-key",
            epoch: try CanonicalPositiveDecimal(1)
        )
        let event = try ExchangeEventIdentifier(
            system: "https://study.example.org/fhir/NamingSystem/grove-event-v0",
            producerInstance: try #require(UUID(uuidString: "6f9d1c4a-2b7e-4f18-9c33-5a1d0e7b2c48")),
            sequence: 1
        )
        var patient = ModelsR4.Patient()
        patient.id = "GroveQuestionnairePatientExample"
        patient.identifier = [
    Identifier(
                system: FHIRPrimitive(FHIRURI(stringLiteral: "https://example.org/research/participant-id")),
                value: "participant-001".asFHIRStringPrimitive()
            )
        ]
        return QuestionnaireExtractionContext(
            patient: patient,
            eventIdentifier: event,
            identityScope: scope,
            repositoryScope: try BusinessIdentifier(
                system: IdentifierSystem("urn:uuid:1f5c58aa-6ec6-4e79-a682-829a9debd3f5"),
                value: "default"
            ),
            entryNodeIdentifierSystem: try IdentifierSystem(
                "https://study.example.org/fhir/NamingSystem/grove-entry-node-v0"
            ),
            conversionInstant: Date(timeIntervalSince1970: 1_787_931_125)
        )
    }

    /// The projected graph, shared with the conformance fixture emitter.
    static func projectedGraph() throws -> ExchangeGraph {
        try projected().graph
    }

    private static func projected() throws -> (graph: ExchangeGraph, observations: [Observation]) {
        let graph = try QuestionnaireExchangeProjection.exchangeGraph(
            questionnaire: try fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
            response: try fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self),
            context: try context()
        )
        let observations = graph.bundle.entry?.compactMap { entry -> Observation? in
            guard case .observation(let observation)? = entry.resource else {
                return nil
            }
            return observation
        } ?? []
        return (graph, observations)
    }

    private static func observation(
        _ observations: [Observation],
        code: String
    ) throws -> Observation {
        try #require(observations.first {
            $0.code.coding?.first?.code?.value?.string == code
        })
    }

    private static func syntheticPair(
        code: (system: String, value: String),
        marking: Extension,
        answer: QuestionnaireResponseItemAnswer.ValueX
    ) throws -> (ModelsR4.Questionnaire, ModelsR4.QuestionnaireResponse) {
        var questionnaire = try fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self)
        var item = QuestionnaireItem(
            linkId: "synthetic".asFHIRStringPrimitive(),
            type: FHIRPrimitive(.choice)
        )
        item.code = [
    Coding(
                code: code.value.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: code.system))
            )
        ]
        item.extension = [marking]
        questionnaire.item = (questionnaire.item ?? []) + [item]
        var response = try fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        var answered = QuestionnaireResponseItem(linkId: "synthetic".asFHIRStringPrimitive())
        answered.answer = [QuestionnaireResponseItemAnswer(value: answer)]
        response.item = (response.item ?? []) + [answered]
        return (questionnaire, response)
    }

    // MARK: The Guide's Worked Example

    @Test("The Home Vitals pair extracts its three documented Observations")
    func extractsThreeObservations() throws {
        let (_, observations) = try Self.projected()
        #expect(observations.count == 3)
        let codes = Set(observations.compactMap { $0.code.coding?.first?.code?.value?.string })
        #expect(codes == ["29463-7", "85354-9", "step-count-total"])
    }

    @Test("The weight takes the moment of answering and the answered unit")
    func weightCarriesAuthoredAndUnit() throws {
        let (_, observations) = try Self.projected()
        let weight = try Self.observation(observations, code: "29463-7")
        guard case .quantity(let value)? = weight.value else {
            Issue.record("weight has no quantity")
            return
        }
        #expect(value.value?.value?.decimal == 72.5)
        #expect(value.code?.value?.string == "kg")
        guard case .dateTime(let effective)? = weight.effective else {
            Issue.record("weight has no effectiveDateTime")
            return
        }
        #expect(try effective.value == DateTime("2026-08-28T08:32:00-07:00"))
    }

    @Test("The panel lands both readings on one Observation")
    func panelCarriesBothComponents() throws {
        let (_, observations) = try Self.projected()
        let panel = try Self.observation(observations, code: "85354-9")
        let components = try #require(panel.component)
        #expect(components.count == 2)
        #expect(panel.value == nil)
        var byCode: [String: ObservationComponent] = [:]
        for component in components {
            if let code = component.code.coding?.first?.code?.value?.string {
                byCode[code] = component
            }
        }
        guard case .quantity(let systolic)? = byCode["8480-6"]?.value,
              case .quantity(let diastolic)? = byCode["8462-4"]?.value else {
            Issue.record("panel components are not quantities")
            return
        }
        #expect(systolic.value?.value?.decimal == 118)
        #expect(diastolic.value?.value?.decimal == 76)
        #expect(systolic.code?.value?.string == "mm[Hg]")
    }

    @Test("Every Observation takes the response's exact authored instant, and issues it")
    func everyObservationTakesAuthored() throws {
        let (_, observations) = try Self.projected()
        let authored = try DateTime("2026-08-28T08:32:00-07:00")
        for observation in observations {
            guard case .dateTime(let effective)? = observation.effective else {
                Issue.record("observation has no effectiveDateTime")
                continue
            }
            #expect(effective.value == authored)
            #expect(observation.issued != nil)
        }
    }

    @Test("The step count takes its fixed unit from the instrument")
    func stepCountCarriesTheFixedUnit() throws {
        let (_, observations) = try Self.projected()
        let steps = try Self.observation(observations, code: "step-count-total")
        guard case .quantity(let value)? = steps.value else {
            Issue.record("step count has no quantity")
            return
        }
        #expect(value.value?.value?.decimal == 8432)
        #expect(value.code?.value?.string == "{steps}")
        #expect(steps.category == nil)
    }

    @Test("Every output carries the envelope: identities, subject, manual entry, derivation")
    func outputsCarryTheMobileEnvelope() throws {
        let (_, observations) = try Self.projected()
        for observation in observations {
            let roles = Set(observation.identifier?.compactMap {
                $0.type?.coding?.first?.code?.value?.string
            } ?? [])
            #expect(roles == ["source-record", "source-output"])
            #expect(observation.subject?.reference?.value?.string.hasPrefix("urn:uuid:") == true)
            #expect(observation.derivedFrom?.count == 1)
            let recording = observation.extension?.first {
                $0.url.value?.url.absoluteString.hasSuffix("grove-recording-method") == true
            }
            guard case .codeableConcept(let method)? = recording?.value else {
                Issue.record("recording method missing")
                continue
            }
            #expect(method.coding?.first?.code?.value?.string == "manual-entry")
        }
    }

    @Test("The writer context becomes the application and host snapshots")
    func writerContextBecomesDevices() throws {
        let (graph, _) = try Self.projected()
        let devices = graph.bundle.entry?.compactMap { entry -> Device? in
            guard case .device(let device)? = entry.resource else {
                return nil
            }
            return device
        } ?? []
        #expect(devices.count == 2)
        let application = try #require(devices.first { $0.parent != nil })
        let host = try #require(devices.first { $0.parent == nil })
        #expect(application.deviceName?.first?.name.value?.string == "Grove Questionnaire Client")
        #expect(host.modelNumber?.value?.string == "iPhone17,1")
        #expect(host.version?.first?.value.value?.string == "26.0")
        var versions: [String: String] = [:]
        for version in application.version ?? [] {
            if let code = version.type?.coding?.first?.code?.value?.string,
               let value = version.value.value?.string {
                versions[code] = value
            }
        }
        #expect(versions["531975"] == "1.4.0")
        #expect(versions["build"] == "1402")
    }

    @Test("One transform Provenance targets every projected output")
    func provenanceTargetsEveryOutput() throws {
        let (graph, observations) = try Self.projected()
        let provenances = graph.bundle.entry?.compactMap { entry -> Provenance? in
            guard case .provenance(let provenance)? = entry.resource else {
                return nil
            }
            return provenance
        } ?? []
        #expect(provenances.count == 1)
        let provenance = try #require(provenances.first)
        #expect(provenance.activity?.coding?.first?.code?.value?.string == "transform")
        #expect(provenance.target.count == observations.count)
        #expect(provenance.agent.first?.type?.coding?.first?.code?.value?.string == "assembler")
    }

    @Test("The Bundle carries the Patient, and every reference resolves inside it")
    func bundleIsClosed() throws {
        let (graph, _) = try Self.projected()
        let entries = try #require(graph.bundle.entry)
        #expect(entries.count == 8)
        let urls = Set(entries.compactMap { $0.fullUrl?.value?.url.absoluteString })
        let kinds = entries.compactMap { entry -> String? in
            guard let resource = entry.resource else {
                return nil
            }
            return ResourceProxy(with: resource.get()).resourceType
        }
        #expect(kinds.contains("Patient"))
        var references: [String] = []
        func collect(_ value: Any) {
            let mirror = Mirror(reflecting: value)
            for child in mirror.children {
                if let reference = child.value as? Reference,
                   let literal = reference.reference?.value?.string {
                    references.append(literal)
                }
                collect(child.value)
            }
        }
        for entry in entries {
            collect(entry as Any)
        }
        for reference in references {
            #expect(urls.contains(reference), "\(reference) does not resolve inside the Bundle")
        }
    }

    @Test("The projection is deterministic")
    func projectionIsDeterministic() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(Self.projected().graph.bundle)
        let second = try encoder.encode(Self.projected().graph.bundle)
        #expect(first == second)
    }

    // MARK: The Guide's Golden Bundle

    /// The projection reproduces the guide's committed bundle wherever the contract makes the
    /// value derivable, and reproduces the protocol's canonical minting where it does not.
    ///
    /// The keyless entry-node keys and their deterministic URNs match the committed bundle byte
    /// for byte. The HMAC identities are asserted against vectors minted with the protocol's own
    /// Python implementation and the published conformance key: the committed bundle's HMAC
    /// values do not correspond to canonical preimages and are pattern-checked only by the
    /// guide's gates, which is reported as an upstream fixture defect.
    @Test("Keyless derivations match the guide's bundle; identities match the canonical mint")
    func matchesTheGuidesExchangeBundle() throws {
        let url = try #require(Bundle.module.url(forResource: "HomeVitals_bundle", withExtension: "json"))
        let golden = try JSONDecoder().decode(GoldenBundle.self, from: Data(contentsOf: url))
        let (graph, observations) = try Self.projected()

        #expect(graph.bundle.identifier?.value?.value?.string == golden.identifier.value)
        #expect(graph.bundle.timestamp?.value?.description == golden.timestamp)

        let entries = try #require(graph.bundle.entry)
        #expect(entries.count == golden.entry.count)
        for (mine, theirs) in zip(entries, golden.entry) {
            let key = mine.extension?.first.flatMap { marker -> Identifier? in
                if case .identifier(let identifier) = marker.value {
                    return identifier
                }
                return nil
            }
            let value = key?.value?.value?.string ?? ""
            if value.hasPrefix("n0:") {
                #expect(value == theirs.extension[0].valueIdentifier.value)
                #expect(mine.fullUrl?.value?.url.absoluteString == theirs.fullUrl)
            }
        }

        // Minted with Scripts/exchange_protocol.py and testVectors.keyHex, pinning
        // Swift/Python cross-implementation equality of every contract preimage.
        let canonical: [String: String] = [
            "29463-7": "v0:test-key:1:Sl5C8R49XC59xPZHI5adt_i54zOnqjWeZmQ77IPrb4I",
            "85354-9": "v0:test-key:1:TNU37wfhgb5JNXgyf3KhIoH_efRZtu8I8O6O6pZzHxo",
            "step-count-total": "v0:test-key:1:VhCT-zticF5TeGZ-vQWoWqsUvtSeCfzu5KGzr9J-DD0"
        ]
        let sourceRecord = "v0:test-key:1:3RRCwVrPwADSWhUldCvYs2p6H0SC4XvqI0lb7WoPU60"
        for observation in observations {
            let code = try #require(observation.code.coding?.first?.code?.value?.string)
            var values: [String: String] = [:]
            for identifier in observation.identifier ?? [] {
                if let role = identifier.type?.coding?.first?.code?.value?.string {
                    values[role] = identifier.value?.value?.string ?? ""
                }
            }
            #expect(values["source-record"] == sourceRecord)
            #expect(values["source-output"] == canonical[code])
        }
    }

    // MARK: Beyond the Guide's Example

    @Test("A coded answer the measurement admits extracts as a CodeableConcept")
    func codedAnswerExtracts() throws {
        let (questionnaire, response) = try Self.syntheticPair(
            code: (
                system: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-mobile-measurement",
                value: "intermenstrual-bleeding"
            ),
            marking: Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.observationExtract)),
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            ),
            answer: .coding(Coding(
                code: "present".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(
                    stringLiteral: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-intermenstrual-bleeding"
                ))
            ))
        )
        let graph = try QuestionnaireExchangeProjection.exchangeGraph(
            questionnaire: questionnaire,
            response: response,
            context: try Self.context()
        )
        let observations = graph.bundle.entry?.compactMap { entry -> Observation? in
            guard case .observation(let observation)? = entry.resource else {
                return nil
            }
            return observation
        } ?? []
        let bleeding = try Self.observation(observations, code: "intermenstrual-bleeding")
        guard case .codeableConcept(let concept)? = bleeding.value else {
            Issue.record("coded answer did not extract as a CodeableConcept")
            return
        }
        #expect(concept.coding?.first?.code?.value?.string == "present")
    }

    @Test("A coded answer outside the measurement's admitted set refuses")
    func codedAnswerOutsideTheSetRefuses() throws {
        let (questionnaire, response) = try Self.syntheticPair(
            code: (
                system: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-mobile-measurement",
                value: "intermenstrual-bleeding"
            ),
            marking: Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.observationExtract)),
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            ),
            answer: .coding(Coding(
                code: "torrential".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(
                    stringLiteral: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-intermenstrual-bleeding"
                ))
            ))
        )
        #expect(throws: ObservationExtractionError.answerNotInMeasurement(
            linkID: "synthetic",
            code: "torrential"
        )) {
            try QuestionnaireExchangeProjection.exchangeGraph(
                questionnaire: questionnaire,
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("A member relationship refuses until its linkage exists")
    func memberRelationshipRefuses() throws {
        let (questionnaire, response) = try Self.syntheticPair(
            code: (
                system: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-mobile-measurement",
                value: "intermenstrual-bleeding"
            ),
            marking: Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.observationExtract)),
                value: .code("member".asFHIRStringPrimitive())
            ),
            answer: .coding(Coding(
                code: "present".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(
                    stringLiteral: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-intermenstrual-bleeding"
                ))
            ))
        )
        #expect(throws: ObservationExtractionError.unsupportedRelationship(
            linkID: "synthetic",
            relationship: "member"
        )) {
            try QuestionnaireExchangeProjection.exchangeGraph(
                questionnaire: questionnaire,
                response: response,
                context: try Self.context()
            )
        }
    }

    // MARK: Refusals

    @Test("An instrument marking nothing refuses before any identity is minted")
    func unmarkedInstrumentRefuses() throws {
        var questionnaire: ModelsR4.Questionnaire = try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self)
        let response: ModelsR4.QuestionnaireResponse = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        questionnaire.item = questionnaire.item?.map { item in
            var item = item
            item.extension = nil
            item.item = item.item?.map { child in
                var child = child
                child.extension = nil
                return child
            }
            return item
        }
        #expect(throws: ObservationExtractionError.noExtractableMeasurements) {
            try QuestionnaireExchangeProjection.exchangeGraph(
                questionnaire: questionnaire,
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("An in-progress response does not project")
    func inProgressResponseRefuses() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.status = FHIRPrimitive(.inProgress)
        #expect(throws: ObservationExtractionError.responseNotCompleted(status: "in-progress")) {
            try QuestionnaireExchangeProjection.exchangeGraph(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("An answer in the wrong unit does not project")
    func wrongUnitRefuses() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        let weightIndex = try #require(response.item?.firstIndex { $0.linkId.value?.string == "body-weight" })
        guard case .quantity(var quantity)? = response.item?[weightIndex].answer?.first?.value else {
            Issue.record("weight answer is not a quantity")
            return
        }
        quantity.code = "[lb_av]".asFHIRStringPrimitive()
        response.item?[weightIndex].answer?[0].value = .quantity(quantity)
        #expect(throws: ObservationExtractionError.unitMismatch(
            linkID: "body-weight",
            expected: "kg",
            answered: "[lb_av]"
        )) {
            try QuestionnaireExchangeProjection.exchangeGraph(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("A response without writer context and no local writer does not project")
    func missingWriterContextRefuses() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.extension = response.extension?.filter {
            $0.url.value?.url.absoluteString.hasSuffix("grove-questionnaire-writer-context") == false
        }
        #expect(throws: ObservationExtractionError.writerContextMissing) {
            try QuestionnaireExchangeProjection.exchangeGraph(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }
}

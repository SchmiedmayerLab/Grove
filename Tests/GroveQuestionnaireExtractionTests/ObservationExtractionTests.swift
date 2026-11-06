//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
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
    let value: String
}

private struct GoldenEntryExt: Decodable {
    let valueIdentifier: GoldenIdentifier
}

private struct GoldenResource: Decodable {
    let resourceType: String
}

private struct GoldenEntry: Decodable {
    let fullUrl: String
    let `extension`: [GoldenEntryExt]
    let resource: GoldenResource
}

private struct GoldenBundle: Decodable {
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

    /// The guide's deployment, as the projection seam takes it.
    private static func context() throws -> QuestionnaireExtractionContext {
        QuestionnaireExtractionContext(
            patient: try QuestionnaireExportFixtures.patient,
            subject: try QuestionnaireExportFixtures.pseudonym,
            identityScope: try QuestionnaireExportFixtures.identityScope,
            repositoryScope: try QuestionnaireExportFixtures.repositoryScope,
            conversionInstant: QuestionnaireExportFixtures.instant
        )
    }

    /// The projected record, shared with the conformance fixture emitter.
    static func projectedRecord() throws -> ExchangeRecord {
        try projected().record
    }

    private static func projected() throws -> (record: ExchangeRecord, observations: [Observation]) {
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: try fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
            response: try fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self),
            context: try context()
        )
        return (record, try record.observations)
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

    /// The Home Vitals response without the named items, as a form filler leaves questions the
    /// participant skipped; a group left with no answered child is omitted with them.
    private static func response(skipping linkIDs: Set<String>) throws -> ModelsR4.QuestionnaireResponse {
        func answered(_ items: [QuestionnaireResponseItem]) -> [QuestionnaireResponseItem] {
            items.compactMap { item -> QuestionnaireResponseItem? in
                guard let linkID = item.linkId.value?.string, !linkIDs.contains(linkID) else {
                    return nil
                }
                guard let children = item.item else {
                    return item
                }
                let remaining = answered(children)
                guard !remaining.isEmpty else {
                    return nil
                }
                var kept = item
                kept.item = remaining
                return kept
            }
        }
        var response = try fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.item = answered(response.item ?? [])
        return response
    }

    /// The Home Vitals instrument with the named top-level item declared `required`.
    private static func questionnaire(requiring linkID: String) throws -> ModelsR4.Questionnaire {
        var questionnaire = try fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self)
        let index = try #require(questionnaire.item?.firstIndex { $0.linkId.value?.string == linkID })
        questionnaire.item?[index].required = FHIRPrimitive(FHIRBool(true))
        return questionnaire
    }

    // MARK: The Guide's Worked Example

    @Test("The Home Vitals pair extracts its two documented Observations")
    func extractsTwoObservations() throws {
        let (_, observations) = try Self.projected()
        #expect(observations.count == 2)
        let codes = Set(observations.compactMap { $0.code.coding?.first?.code?.value?.string })
        #expect(codes == ["29463-7", "85354-9"])
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
        let expected: DateTime = "2026-08-28T08:32:00-07:00"
        #expect(effective.value == expected)
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
        let authored: DateTime = "2026-08-28T08:32:00-07:00"
        for observation in observations {
            guard case .dateTime(let effective)? = observation.effective else {
                Issue.record("observation has no effectiveDateTime")
                continue
            }
            #expect(effective.value == authored)
            #expect(observation.issued != nil)
        }
    }

    @Test("A measurement that is only ever effective over a Period does not extract")
    func periodEffectiveMeasurementIsRefused() throws {
        let (questionnaire, response) = try Self.syntheticPair(
            code: (
                system: "https://grovealliance.org/fhir/mobile/CodeSystem/grove-mobile-measurement",
                value: "step-count-total"
            ),
            marking: Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.observationExtract)),
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            ),
            answer: .integer(FHIRPrimitive(FHIRInteger(8432)))
        )
        #expect(throws: ObservationExtractionError.measurementRequiresEffectivePeriod(
            linkID: "synthetic",
            measurement: "step-count"
        )) {
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: questionnaire,
                response: response,
                context: try Self.context()
            )
        }
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
            #expect(observation.performer == [try #require(observation.subject)])
            #expect(observation.derivedFrom?.count == 1)
            let recording = observation.extension?.first {
                $0.url.value?.url.absoluteString.hasSuffix("grove-recording-method") == true
            }
            guard case .coding(let method)? = recording?.value else {
                Issue.record("recording method missing")
                continue
            }
            #expect(method.code?.value?.string == "manual-entry")
        }
    }

    @Test("The writer context becomes the application and host snapshots")
    func writerContextBecomesDevices() throws {
        let devices = try Self.projected().record.devices
        #expect(devices.count == 2)
        let application = try #require(devices.first { $0.parent != nil })
        let host = try #require(devices.first { $0.parent == nil })
        #expect(application.deviceName?.first?.name.value?.string == "Grove Questionnaire Client")
        #expect(application.identifier?.contains(try QuestionnaireExportFixtures.writer().applicationIdentifier.fhirIdentifier) == true)
        #expect(application.statedVersions == ["531975": "1.4.0", "build": "1402"])
        #expect(host.modelNumber?.value?.string == "iPhone17,1")
        #expect(host.statedVersions == ["os-name": "iOS", "os-version": "26.0", "os-build": "23A341"])
    }

    @Test("One transform Provenance targets every projected output")
    func provenanceTargetsEveryOutput() throws {
        let (record, observations) = try Self.projected()
        let provenance = try record.provenance
        #expect(provenance.activity?.coding?.first?.code?.value?.string == "transform")
        #expect(provenance.target.count == observations.count)
        #expect(provenance.agent.first?.type?.coding?.first?.code?.value?.string == "assembler")
    }

    @Test("The Bundle carries the Patient, and every reference resolves inside it")
    func bundleIsClosed() throws {
        let entries = try #require(try Self.projected().record.bundle.entry)
        #expect(entries.count == 7)
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
        let first = try Self.projected().record
        let second = try Self.projected().record
        #expect(first.json == second.json)
    }

    // MARK: The Guide's Golden Bundle

    /// The projection reproduces the guide's committed bundle wherever the guide's content is the projection's.
    ///
    /// The Patient, the response and both Observations keep the guide's fullUrls, so their keys match it byte for byte.
    /// The Device snapshots and the record version digest whole bodies, and the guide writes those by hand: its Device
    /// versions state no display and name the operating system first, and its codes state displays the catalog does not.
    /// `guidesBundleRecomputes` holds those keys to the guide's own bytes instead.
    @Test("Keys and fullUrls match the guide's bundle wherever the content does")
    func matchesTheGuidesExchangeBundle() throws {
        let url = try #require(Bundle.module.url(forResource: "HomeVitals_bundle", withExtension: "json"))
        let golden = try JSONDecoder().decode(GoldenBundle.self, from: Data(contentsOf: url))
        let (record, observations) = try Self.projected()
        let bundle = try record.bundle

        #expect(bundle.timestamp?.value?.description == golden.timestamp)

        let entries = try #require(bundle.entry)
        #expect(entries.compactMap { $0.resource?.resourceType } == golden.entry.map(\.resource.resourceType))
        for (mine, theirs) in zip(entries, golden.entry) where !["Device", "Provenance"].contains(theirs.resource.resourceType) {
            let key = mine.extension?.first.flatMap { marker -> Identifier? in
                if case .identifier(let identifier) = marker.value {
                    return identifier
                }
                return nil
            }
            #expect(key?.value?.value?.string == theirs.extension[0].valueIdentifier.value)
            #expect(mine.fullUrl?.value?.url.absoluteString == theirs.fullUrl)
        }

        // The guide publishes these under testVectors.identities as
        // questionnaire-extraction-{source-record,body-weight-output,blood-pressure-output},
        // pinning Swift/Python cross-implementation equality of every contract preimage.
        let canonical: [String: String] = [
            "29463-7": "v0:test-key:1:oY5ARo6F_wNj5wVdtFqORMdUwZ__B9kQ6GW1RSaEz10",
            "85354-9": "v0:test-key:1:ljzpyfYa15oOpj_A37-cd-_8JXqQwwfomR9iT0gct6g"
        ]
        let sourceRecord = "v0:test-key:1:7_7dmqTFxPH01QGTycmp8nIPty7WwphH2X0ZaV-p3wk"
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

    /// Reads the guide's Bundle as a consumer does, and recomputes what only the key holder can: the record version and
    /// every content key, which the guide publishes under testVectors.identities as
    /// questionnaire-extraction-{record-version,host-snapshot,bundle-application-snapshot,patient-snapshot,response-snapshot}.
    @Test("The guide's bundle reads back as one record, and every key it publishes recomputes")
    func guidesBundleRecomputes() throws {
        let url = try #require(Bundle.module.url(forResource: "HomeVitals_bundle", withExtension: "json"))
        let json = try Data(contentsOf: url)
        let scope = try QuestionnaireExportFixtures.identityScope
        let record = try ExchangeRecord(validating: json)
        #expect(record.kind == .active)
        #expect(record.subject == (try QuestionnaireExportFixtures.pseudonym))
        #expect(record.version.identifier.identifier.value == "v0:test-key:1:RIiSEVoX9fCoWyNMZvL3QAPxmelpxzePPzRbQOfPtb0")
        try record.verifyVersion(in: scope)
        let graph = try ExchangeGraph(validating: json, kind: .active)
        try graph.validateDerivedKeys(in: scope)
        let keys = graph.bundle.entry?.compactMap { entry -> String? in
            guard case .identifier(let key)? = entry.extension?.first?.value else {
                return nil
            }
            return key.value?.value?.string
        } ?? []
        #expect(Set(keys).isSuperset(of: [
            "v0:test-key:1:BJ68B1Ln-JzOKPDWOevEmnjQNsX0BheIosEdSGgRV1A",
            "v0:test-key:1:fZBQIWIeM0SUmHvsH68yGnBNNNz_jdJ9SFkWOMGuxKw",
            "v0:test-key:1:0Bqdjt59Tx6RlSNPK625TzKjLgrZiw6OHtnobZsfskk",
            "v0:test-key:1:fE9dYA07a6yqebbrEAnnljfpr727wsDXFFvPxDPLuPI"
        ]))
    }

    // MARK: Beyond the Guide's Example

    @Test("Workout segment codes remain bound to their declared systems", arguments: [
        ("lap", "grove-workout-segment-type", true),
        ("running", "grove-workout-activity", true),
        ("running", "grove-workout-segment-type", false),
        ("lap", "grove-workout-activity", false),
        ("not-a-segment", "grove-workout-segment-type", false),
        ("running", "not-a-system", false)
    ])
    func workoutSegmentResultBindings(code: String, system: String, admitted: Bool) {
        #expect(MeasurementCatalog.workoutSegment.admitsResult(
            code: code,
            system: "https://grovealliance.org/fhir/mobile/CodeSystem/\(system)"
        ) == admitted)
    }

    @Test("A coded answer uses allowedValues when the catalog has no display-bearing resultCodes")
    func codedAnswerUsesAllowedValues() throws {
        let contract = HealthKitMeasurementCatalog.bladderIncontinence
        #expect(contract.resultCodes.isEmpty)
        let system = try #require(contract.resultCodeSystem)
        let (questionnaire, response) = try Self.syntheticPair(
            code: (system: contract.code.system, value: contract.code.code),
            marking: Extension(
                url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.observationExtract)),
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            ),
            answer: .coding(Coding(
                code: "mild".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: system))
            ))
        )
        let extracted = try QuestionnaireObservationExtractor(questionnaire: questionnaire, response: response).extract()
        let measurement = try #require(extracted.first { $0.contract.id == contract.id })
        guard case .codeableConcept(let concept) = measurement.value else {
            Issue.record("coded answer did not extract as a CodeableConcept")
            return
        }
        #expect(concept.coding?.first?.code?.value?.string == "mild")
    }

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
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: questionnaire,
            response: response,
            context: try Self.context()
        )
        let bleeding = try Self.observation(record.observations, code: "intermenstrual-bleeding")
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
            try QuestionnaireExchangeProjection.exchangeRecord(
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
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: questionnaire,
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("A panel of integer answers takes the unit its questionnaire-unit fixes")
    func integerComponentsTakeTheFixedUnit() throws {
        var questionnaire = try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self)
        let panelIndex = try #require(questionnaire.item?.firstIndex { $0.linkId.value?.string == "blood-pressure" })
        let fixedUnit = Extension(
            url: FHIRPrimitive(FHIRURI(stringLiteral: ExtractionCanonical.questionnaireUnit)),
            value: .coding(Coding(
                code: "mm[Hg]".asFHIRStringPrimitive(),
                display: "mm[Hg]".asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: "http://unitsofmeasure.org"))
            ))
        )
        let components = questionnaire.item?[panelIndex].item?.map { child in
            var child = child
            child.type = FHIRPrimitive(.integer)
            child.extension = (child.extension ?? []).filter {
                $0.url.value?.url.absoluteString == ExtractionCanonical.observationExtract
            } + [fixedUnit]
            return child
        }
        questionnaire.item?[panelIndex].item = components
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        let answeredIndex = try #require(response.item?.firstIndex { $0.linkId.value?.string == "blood-pressure" })
        let readings: [(linkID: String, value: Int32)] = [("systolic", 118), ("diastolic", 76)]
        response.item?[answeredIndex].item = readings.map { reading in
            var item = QuestionnaireResponseItem(linkId: reading.linkID.asFHIRStringPrimitive())
            item.answer = [QuestionnaireResponseItemAnswer(value: .integer(FHIRPrimitive(FHIRInteger(reading.value))))]
            return item
        }
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: questionnaire,
            response: response,
            context: try Self.context()
        )
        let panel = try Self.observation(record.observations, code: "85354-9")
        var byCode: [String: Quantity] = [:]
        for component in panel.component ?? [] {
            if let code = component.code.coding?.first?.code?.value?.string,
               case .quantity(let quantity)? = component.value {
                byCode[code] = quantity
            }
        }
        #expect(byCode["8480-6"]?.value?.value?.decimal == 118)
        #expect(byCode["8462-4"]?.value?.value?.decimal == 76)
        #expect(byCode["8480-6"]?.code?.value?.string == "mm[Hg]")
        #expect(byCode["8462-4"]?.code?.value?.string == "mm[Hg]")
    }

    // MARK: Unanswered Items

    @Test("A skipped optional panel leaves the answered measurement to extract")
    func skippedPanelLeavesTheAnsweredMeasurement() throws {
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
            response: try Self.response(skipping: ["systolic", "diastolic"]),
            context: try Self.context()
        )
        let observations = try record.observations
        #expect(observations.count == 1)
        #expect(observations.first?.code.coding?.first?.code?.value?.string == "29463-7")
    }

    @Test("A skipped optional measurement leaves the answered panel to extract")
    func skippedMeasurementLeavesTheAnsweredPanel() throws {
        // The item stays in the response with no answer: a skip reads the same either way.
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        let weightIndex = try #require(response.item?.firstIndex { $0.linkId.value?.string == "body-weight" })
        response.item?[weightIndex].answer = nil
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
            response: response,
            context: try Self.context()
        )
        let observations = try record.observations
        #expect(observations.count == 1)
        let panel = try Self.observation(observations, code: "85354-9")
        #expect(panel.component?.count == 2)
    }

    @Test("A response answering no marked item extracts nothing and states no record")
    func unansweredResponseExtractsNothing() throws {
        let questionnaire = try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self)
        let response = try Self.response(skipping: ["body-weight", "systolic", "diastolic"])
        let extracted = try QuestionnaireObservationExtractor(questionnaire: questionnaire, response: response).extract()
        #expect(extracted.isEmpty)
        #expect(throws: ObservationExtractionError.noExtractableMeasurements) {
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: questionnaire,
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("A required measurement left unanswered extracts nothing and keeps the others")
    func requiredUnansweredMeasurementExtractsNothing() throws {
        // `required` binds only while the item is enabled, which extraction cannot evaluate; the pair
        // validator enforces it. Refusing here would drop every other reading of the response.
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: try Self.questionnaire(requiring: "body-weight"),
            response: try Self.response(skipping: ["body-weight"]),
            context: try Self.context()
        )
        let observations = try record.observations
        #expect(observations.count == 1)
        _ = try Self.observation(observations, code: "85354-9")
    }

    @Test("A panel answered only in part refuses rather than dropping the answered reading")
    func partiallyAnsweredPanelRefuses() throws {
        #expect(throws: ObservationExtractionError.componentIncomplete(measurement: "blood-pressure", missing: "8462-4")) {
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: try Self.response(skipping: ["diastolic"]),
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
            try QuestionnaireExchangeProjection.exchangeRecord(
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
            try QuestionnaireExchangeProjection.exchangeRecord(
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
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("A response authored by someone other than the subject refuses instead of being re-attributed")
    func foreignAuthorRefuses() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.author = Reference(reference: "Practitioner/caregiver-7".asFHIRStringPrimitive())
        #expect(throws: ObservationExtractionError.authorIsNotTheSubject) {
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("A response sourced from someone other than the subject refuses")
    func foreignSourceRefuses() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.source = Reference(reference: "RelatedPerson/partner-2".asFHIRStringPrimitive())
        #expect(throws: ObservationExtractionError.sourceIsNotTheSubject) {
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }

    @Test("An authorless response states no performer instead of inventing one")
    func authorlessResponseStatesNoPerformer() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.author = nil
        let record = try QuestionnaireExchangeProjection.exchangeRecord(
            questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
            response: response,
            context: try Self.context()
        )
        for observation in try record.observations {
            #expect(observation.performer == nil)
        }
    }

    @Test("A response without writer context does not project")
    func missingWriterContextRefuses() throws {
        var response = try Self.fixture("HomeVitals_response", as: ModelsR4.QuestionnaireResponse.self)
        response.extension = response.extension?.filter {
            $0.url.value?.url.absoluteString.hasSuffix("grove-questionnaire-writer-context") == false
        }
        #expect(throws: ObservationExtractionError.writerContextMissing) {
            try QuestionnaireExchangeProjection.exchangeRecord(
                questionnaire: try Self.fixture("HomeVitals_questionnaire", as: ModelsR4.Questionnaire.self),
                response: response,
                context: try Self.context()
            )
        }
    }
}

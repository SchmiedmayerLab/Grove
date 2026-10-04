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


@Suite("Questionnaire FHIR Exporter")
struct QuestionnaireFHIRExporterTests {
    private typealias Fixtures = QuestionnaireExportFixtures

    private static func sequences(_ exports: [QuestionnaireFHIRExporter.Export]) -> [String?] {
        exports.map { $0.graph?.eventIdentifier.sequence.rawValue }
    }

    /// The guide's response, amended: the same response identifier with another answer.
    private static func amended() throws -> QuestionnaireFHIRExporter.Record {
        try Fixtures.guideRecord { response in
            response.status = FHIRPrimitive(.amended)
            let weight = try #require(response.item?.firstIndex { $0.linkId.value?.string == "body-weight" })
            guard case .quantity(var quantity)? = response.item?[weight].answer?.first?.value else {
                throw CocoaError(.featureUnsupported)
            }
            quantity.value = FHIRPrimitive(FHIRDecimal(Decimal(721) / 10))
            response.item?[weight].answer?[0].value = .quantity(quantity)
        }
    }

    @Test("A redelivery before release restates the event, even from a producer rebuilt with new enrollments")
    func redeliveryReproducesEvents() throws {
        let storage = ExchangeProducer.InMemoryStorage()
        let exporter = try Fixtures.exporter(Fixtures.producer(storage: storage))
        let (first, receipt) = try Fixtures.collect(exporter, [try Fixtures.guideRecord()])
        #expect(Self.sequences(first) == ["1"])
        #expect(first.map(\.responseIdentifier) == ["home-vitals-2026-08-28"])

        let rebuilt = try Fixtures.exporter(Fixtures.producer(studies: [Fixtures.study("study-a")], storage: storage))
        let (again, againReceipt) = try Fixtures.collect(rebuilt, [try Fixtures.guideRecord()], at: Fixtures.instant.addingTimeInterval(3_600))
        #expect(again.map(\.graph?.json) == first.map(\.graph?.json))

        receipt.release()
        againReceipt.release()
        let (next, _) = try Fixtures.collect(rebuilt, [try Fixtures.guideRecord()])
        #expect(Self.sequences(next) == ["2"])
        #expect(next.first?.graph?.resourceTypes.contains("ResearchStudy") == true)
    }

    @Test("A refused record reserves nothing and the call goes on")
    func refusalsDoNotEndTheCall() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let inProgress = try Fixtures.guideRecord { $0.status = FHIRPrimitive(.inProgress) }
        let (exports, _) = try Fixtures.collect(exporter, [inProgress, try Fixtures.guideRecord()])
        guard case .refused(let refusal) = exports.first?.outcome else {
            Issue.record("the in-progress response was not refused")
            return
        }
        #expect(refusal == .responseNotCompleted(status: "in-progress"))
        #expect(Self.sequences(exports) == [nil, "1"])
    }

    @Test("Identity and graph failures are refusals of their own record")
    func identityAndGraphFailuresAreRefusals() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let blankIdentifier = try Fixtures.guideRecord { $0.identifier = Identifier(system: $0.identifier?.system, value: "") }
        // A study reference the Bundle cannot resolve fails the graph's governed-reference rule.
        let foreignStudy = try Fixtures.guideRecord { response in
            response.identifier = Identifier(system: response.identifier?.system, value: "home-vitals-foreign-study")
            response.extension = (response.extension ?? []) + [
                Extension(
                    url: Canonicals.researchStudy,
                    value: .reference(Reference(reference: "urn:uuid:00000000-0000-4000-8000-000000000000"))
                )
            ]
        }
        let (exports, _) = try Fixtures.collect(exporter, [blankIdentifier, foreignStudy, try Fixtures.guideRecord()])
        guard case .refused(.opaqueIdentity) = exports[0].outcome else {
            Issue.record("a blank response identifier is not an identity refusal: \(String(describing: exports[0].outcome))")
            return
        }
        guard case .refused(.exchangeGraph) = exports[1].outcome else {
            Issue.record("an unresolvable study reference is not a graph refusal: \(String(describing: exports[1].outcome))")
            return
        }
        #expect(exports[2].graph != nil)
    }

    @Test("A response named twice with other content keeps its first event; the same content shares it")
    func duplicatesInOneCall() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let (conflicting, _) = try Fixtures.collect(exporter, [try Fixtures.guideRecord(), try Self.amended()])
        #expect(Self.sequences(conflicting) == ["1", nil])
        guard case .refused(.conflictingDuplicate) = conflicting.last?.outcome else {
            Issue.record("the amended duplicate was not refused")
            return
        }
        let (repeated, _) = try Fixtures.collect(exporter, [try Fixtures.guideRecord(), try Fixtures.guideRecord()])
        #expect(Self.sequences(repeated) == ["1", "1"])
        #expect(repeated[0].graph?.json == repeated[1].graph?.json)
    }

    @Test("Another response or another revision of the instrument under a reserved response mints a new event")
    func contentChangesMintNewEvents() throws {
        let guide = try Fixtures.guideRecord()
        var questionnaire = guide.questionnaire
        questionnaire.title = "Home Vitals, revised wording"
        let retitled = QuestionnaireFHIRExporter.Record(questionnaire: questionnaire, response: guide.response)
        // Each change alone against the guide's reserved pair, so neither masks the other.
        for changed in [try Self.amended(), retitled] {
            let exporter = try Fixtures.exporter(Fixtures.producer())
            let (first, _) = try Fixtures.collect(exporter, [guide])
            let (again, _) = try Fixtures.collect(exporter, [changed])
            #expect(Self.sequences(first + again) == ["1", "2"])
        }
    }

    /// A reservation keeps the fingerprint it was made under, and every later export compares against it, across launches
    /// and app updates: a build that derives the same request's fingerprint differently gives every pending reservation a
    /// new sequence on redelivery, so the derivation, call parts and record parts alike, changes only on purpose, as
    /// with an output revision.
    @Test("The guide's pair fingerprints to a known answer")
    func requestFingerprintIsAKnownAnswer() throws {
        try #require(
            ExchangeGraphAssembler.outputRevision == 1 && QuestionnaireExchangeProjection.outputRevision == 1,
            "a revision bump restates the answer"
        )
        let plan = QuestionnaireFHIRExporter.Plan(try Fixtures.guideRecord(), exporter: try Fixtures.exporter(Fixtures.producer()))
        let request = try plan.content.get().request
        #expect(request.fingerprint == "N47uKqCVhHJ4Ea_fglb8zkHHQyF690pjJxs7t4YcmC8")
    }

    /// A response built in memory can carry a named zone, while its JSON, which the request fingerprints, states only
    /// the offset the authored value had. Both forms are one request, so they must state one graph, even when the
    /// zone's offset at the conversion instant differs from the authored one.
    @Test("A response with a named zone and its decoded JSON restate one event byte for byte across a daylight-saving change")
    func namedZoneAndItsJSONRestateOneEvent() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        // Authored in summer time, at +02:00; converted in December, when the zone is at +01:00.
        let authored = try DateTime(date: Date(timeIntervalSince1970: 1_787_931_120), timeZone: berlin)
        let named = try Fixtures.guideRecord { $0.authored = FHIRPrimitive(authored) }
        let decoded = QuestionnaireFHIRExporter.Record(
            questionnaire: named.questionnaire,
            response: try JSONDecoder().decode(ModelsR4.QuestionnaireResponse.self, from: JSONEncoder().encode(named.response))
        )
        try #require(decoded.response.authored?.value?.description == "2026-08-28T17:32:00+02:00")
        try #require(decoded.response.authored?.value?.timeZone != berlin, "decoding keeps only the stated offset")
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let december = Date(timeIntervalSince1970: 1_796_139_125)
        let (first, _) = try Fixtures.collect(exporter, [named], at: december)
        let (again, _) = try Fixtures.collect(exporter, [decoded], at: december.addingTimeInterval(60))
        let graph = try #require(first.first?.graph)
        #expect(Self.sequences(again) == ["1"])
        #expect(again.first?.graph?.json == graph.json)
        let provenance = try #require(graph.bundle.entry?.lazy.compactMap { entry -> ModelsR4.Provenance? in
            if case .provenance(let provenance)? = entry.resource { provenance } else { nil }
        }.first)
        guard case .dateTime(let occurred)? = provenance.occurred else {
            Issue.record("the Provenance states no occurred time")
            return
        }
        #expect(occurred.value?.description == "2026-12-01T17:32:05+02:00", "the conversion instant at the authored offset")
    }

    @Test("A logical subject bundles a Patient stating only the pseudonym")
    func logicalSubjectBundlesThePseudonym() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer(subject: .logical(Fixtures.pseudonym)))
        let graph = try #require(try Fixtures.collect(exporter, [try Fixtures.guideRecord()]).exports.first?.graph)
        let entry = try #require(graph.bundle.entry?.first)
        guard case .patient(let patient)? = entry.resource else {
            Issue.record("the first entry is not the Patient")
            return
        }
        #expect(patient.id == nil)
        #expect(patient.identifier == [try Fixtures.pseudonym.fhirIdentifier])
        let patientURL = entry.fullUrl?.value?.url.absoluteString
        #expect(graph.observations.allSatisfy { $0.subject?.reference?.value?.string == patientURL })
    }

    @Test("An enrolled participant's graph states the study context after the Patient and references it from every Observation")
    func enrollmentsBecomeTheStudyContext() throws {
        let exporter = try Fixtures.exporter(Fixtures.producer(studies: [Fixtures.study("study-a"), Fixtures.study("study-b")]))
        let graph = try #require(try Fixtures.collect(exporter, [try Fixtures.guideRecord()]).exports.first?.graph)
        let study = ["ResearchStudy", "PlanDefinition", "ResearchSubject"]
        #expect(graph.resourceTypes == ["Patient"] + study + study + ["QuestionnaireResponse", "Device", "Device", "Observation", "Observation", "Provenance"])
        let entries = try #require(graph.bundle.entry)
        let studyURLs = entries.filter { $0.resource?.resourceType == "ResearchStudy" }.map { $0.fullUrl?.value?.url.absoluteString }
        for observation in graph.observations {
            let extensions = observation.extension ?? []
            #expect(extensions.map { $0.url.value?.url.absoluteString } == [
                Canonicals.recordingMethod.value?.url.absoluteString,
                Canonicals.gatewayDevice.value?.url.absoluteString,
                Canonicals.researchStudy.value?.url.absoluteString,
                Canonicals.researchStudy.value?.url.absoluteString
            ])
            let references = extensions.dropFirst(2).map { studyExtension -> String? in
                guard case .reference(let reference)? = studyExtension.value else {
                    return nil
                }
                return reference.reference?.value?.string
            }
            #expect(references == studyURLs)
        }
        for entry in entries {
            guard case .researchSubject(let researchSubject)? = entry.resource else {
                continue
            }
            #expect(researchSubject.individual == graph.observations.first?.subject)
        }
    }

    @Test("An error in the receiver ends the call with the reservations kept")
    func receiverErrorsPropagate() throws {
        struct Stop: Error {}
        let exporter = try Fixtures.exporter(Fixtures.producer())
        #expect(throws: Stop.self) {
            try exporter.export([try Fixtures.guideRecord()], at: Fixtures.instant) { _ in throw Stop() }
        }
        let (again, _) = try Fixtures.collect(exporter, [try Fixtures.guideRecord()])
        #expect(Self.sequences(again) == ["1"])
    }

    @Test("Every failure narrows to the refusal domain by its type")
    func failuresNarrowToTheRefusalDomain() {
        struct Unmodelled: Error {}
        #expect(ObservationExtractionError(conversionFailure: ObservationExtractionError.subjectMissing) == .subjectMissing)
        #expect(ObservationExtractionError(conversionFailure: ExchangeIdentityError.invalidInstant) == .exchangeIdentity(.invalidInstant))
        #expect(ObservationExtractionError(conversionFailure: OpaqueIdentityError.reusedIdentifierSystem) == .opaqueIdentity(.reusedIdentifierSystem))
        #expect(ObservationExtractionError(conversionFailure: ExchangeGraphError.missingTimestamp) == .exchangeGraph(.missingTimestamp))
        guard case .unexpectedConversionFailure(let name) = ObservationExtractionError(conversionFailure: Unmodelled()) else {
            Issue.record("an unmodelled failure was relabelled")
            return
        }
        #expect(name.hasSuffix("Unmodelled"))
    }
}

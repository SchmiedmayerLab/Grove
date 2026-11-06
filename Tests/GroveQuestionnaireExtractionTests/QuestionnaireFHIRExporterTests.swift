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

    @Test("A redelivery at the same instant restates the record byte for byte, from any exporter")
    func redeliveryRestatesTheRecord() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let first = try await Fixtures.collect(exporter, [try Fixtures.guideRecord()])
        #expect(first.map(\.responseIdentifier) == ["home-vitals-2026-08-28"])
        let record = try #require(first.first?.record)

        let again = try await Fixtures.collect(exporter, [try Fixtures.guideRecord()])
        #expect(again.first?.record == record)
        let rebuilt = try Fixtures.exporter(Fixtures.producer())
        let elsewhere = try await Fixtures.collect(rebuilt, [try Fixtures.guideRecord()])
        #expect(elsewhere.first?.record == record)
    }

    @Test("A later conversion is a new version of the source record, over the same outputs")
    func laterConversionIsANewVersion() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let first = try await #require(try Fixtures.collect(exporter, [try Fixtures.guideRecord()]).first?.record)
        let exports = try await Fixtures.collect(exporter, [try Fixtures.guideRecord()], at: Fixtures.instant.addingTimeInterval(3_600))
        let later = try #require(exports.first?.record)
        #expect(later.version != first.version)
        #expect(later.sourceRecord == first.sourceRecord)
        #expect(later.outputFullURLs == first.outputFullURLs)
        #expect(later.sharedNodeFullURLs == first.sharedNodeFullURLs)
    }

    @Test("New enrollments give the response's record a new version, stating them")
    func enrollmentsChangeTheVersion() async throws {
        let first = try await Fixtures.exported(Fixtures.guideRecord())
        let enrolled = try Fixtures.exporter(Fixtures.producer(studies: [Fixtures.study("study-a")]))
        let record = try await #require(try Fixtures.collect(enrolled, [try Fixtures.guideRecord()]).first?.record)
        #expect(try record.resourceTypes.contains("ResearchStudy"))
        #expect(record.version != first.version)
        #expect(record.sourceRecord == first.sourceRecord)
    }

    @Test("A refused record emits nothing and the call goes on")
    func refusalsDoNotEndTheCall() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let inProgress = try Fixtures.guideRecord { $0.status = FHIRPrimitive(.inProgress) }
        let exports = try await Fixtures.collect(exporter, [inProgress, try Fixtures.guideRecord()])
        guard case .refused(let refusal) = exports.first?.outcome else {
            Issue.record("the in-progress response was not refused")
            return
        }
        #expect(refusal == .responseNotCompleted(status: "in-progress"))
        #expect(exports.map { $0.record != nil } == [false, true])
    }

    @Test("Identity and graph failures are refusals of their own record")
    func identityAndGraphFailuresAreRefusals() async throws {
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
        let exports = try await Fixtures.collect(exporter, [blankIdentifier, foreignStudy, try Fixtures.guideRecord()])
        guard case .refused(.exchangeIdentity) = exports[0].outcome else {
            Issue.record("a blank response identifier is not an identity refusal: \(String(describing: exports[0].outcome))")
            return
        }
        guard case .refused(.exchangeGraph) = exports[1].outcome else {
            Issue.record("an unresolvable study reference is not a graph refusal: \(String(describing: exports[1].outcome))")
            return
        }
        #expect(exports[2].record != nil)
    }

    @Test("A response named twice in one call states each content once, as versions of one source record")
    func duplicatesInOneCall() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        let repeated = try await Fixtures.collect(exporter, [try Fixtures.guideRecord(), try Fixtures.guideRecord()])
        #expect(repeated[0].record == repeated[1].record)

        let exports = try await Fixtures.collect(exporter, [try Fixtures.guideRecord(), try Self.amended()])
        let original = try #require(exports[0].record)
        let amendment = try #require(exports[1].record)
        #expect(amendment.version != original.version)
        #expect(amendment.sourceRecord == original.sourceRecord)
        #expect(amendment.outputFullURLs == original.outputFullURLs)
        #expect(try amendment.observations.map(\.status.value) == [.amended, .amended])
    }

    @Test("Another revision of the instrument that extracts the same outputs states the same record")
    func instrumentRevisionsEnterTheRecordThroughTheirOutputs() async throws {
        let guide = try Fixtures.guideRecord()
        var questionnaire = guide.questionnaire
        questionnaire.title = "Home Vitals, revised wording"
        let retitled = QuestionnaireFHIRExporter.Record(questionnaire: questionnaire, response: guide.response)
        #expect(try await Fixtures.exported(retitled) == Fixtures.exported(guide))
    }

    /// A response built in memory can carry a named zone, while its JSON states only the offset the authored value had.
    /// Both forms are one response, so they must state one record, even when the zone's offset at the conversion instant
    /// differs from the authored one.
    @Test("A response with a named zone and its decoded JSON restate one record byte for byte across a daylight-saving change")
    func namedZoneAndItsJSONRestateOneRecord() async throws {
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
        let first = try await Fixtures.collect(exporter, [named], at: december)
        let again = try await Fixtures.collect(exporter, [decoded], at: december)
        let record = try #require(first.first?.record)
        #expect(again.first?.record?.json == record.json)
        guard case .dateTime(let occurred)? = try record.provenance.occurred else {
            Issue.record("the Provenance states no occurred time")
            return
        }
        #expect(occurred.value?.description == "2026-12-01T17:32:05+02:00", "the conversion instant at the authored offset")
    }

    @Test("A logical subject bundles a Patient stating only the pseudonym")
    func logicalSubjectBundlesThePseudonym() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer(subject: .logical(Fixtures.pseudonym)))
        let record = try await #require(try Fixtures.collect(exporter, [try Fixtures.guideRecord()]).first?.record)
        let entry = try #require(try record.bundle.entry?.first)
        guard case .patient(let patient)? = entry.resource else {
            Issue.record("the first entry is not the Patient")
            return
        }
        #expect(patient.id == nil)
        #expect(patient.identifier?.first == (try Fixtures.pseudonym.fhirIdentifier))
        let patientURL = entry.fullUrl?.value?.url.absoluteString
        #expect(try record.observations.allSatisfy { $0.subject?.reference?.value?.string == patientURL })
    }

    @Test("An enrolled participant's record states the study context after the Patient and references it from every Observation")
    func enrollmentsBecomeTheStudyContext() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer(studies: [Fixtures.study("study-a"), Fixtures.study("study-b")]))
        let record = try await #require(try Fixtures.collect(exporter, [try Fixtures.guideRecord()]).first?.record)
        let study = ["ResearchStudy", "PlanDefinition", "ResearchSubject"]
        let outputs = ["QuestionnaireResponse", "Device", "Device", "Observation", "Observation", "Provenance"]
        #expect(try record.resourceTypes == ["Patient"] + study + study + outputs)
        let entries = try #require(try record.bundle.entry)
        let studyURLs = entries.filter { $0.resource?.resourceType == "ResearchStudy" }.map { $0.fullUrl?.value?.url.absoluteString }
        let observations = try record.observations
        for observation in observations {
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
            #expect(researchSubject.individual == observations.first?.subject)
        }
    }

    @Test("An error in the receiver ends the call and leaves nothing behind")
    func receiverErrorsPropagate() async throws {
        struct Stop: Error {}
        let exporter = try Fixtures.exporter(Fixtures.producer())
        await #expect(throws: Stop.self) {
            try await exporter.export([try Fixtures.guideRecord()], at: Fixtures.instant) { _ in throw Stop() }
        }
        let again = try await Fixtures.collect(exporter, [try Fixtures.guideRecord()])
        #expect(again.first?.record == (try await Fixtures.exported(Fixtures.guideRecord())))
    }

    @Test("An instant no FHIR instant can state ends the call")
    func unstatableInstantEndsTheCall() async throws {
        let exporter = try Fixtures.exporter(Fixtures.producer())
        await #expect(throws: ExchangeIdentityError.invalidInstant) {
            try await exporter.export([try Fixtures.guideRecord()], at: Date(timeIntervalSince1970: 1e12)) { _ in }
        }
    }

    @Test("Every failure narrows to the refusal domain by its type")
    func failuresNarrowToTheRefusalDomain() {
        struct Unmodelled: Error {}
        #expect(ObservationExtractionError(conversionFailure: ObservationExtractionError.subjectMissing) == .subjectMissing)
        #expect(ObservationExtractionError(conversionFailure: ExchangeIdentityError.invalidInstant) == .exchangeIdentity(.invalidInstant))
        #expect(ObservationExtractionError(conversionFailure: ExchangeIdentityError.invalidKeyID("x")) == .exchangeIdentity(.invalidKeyID("x")))
        #expect(ObservationExtractionError(conversionFailure: ExchangeGraphError.missingTimestamp) == .exchangeGraph(.missingTimestamp))
        guard case .unexpectedConversionFailure(let name) = ObservationExtractionError(conversionFailure: Unmodelled()) else {
            Issue.record("an unmodelled failure was relabelled")
            return
        }
        #expect(name.hasSuffix("Unmodelled"))
    }
}

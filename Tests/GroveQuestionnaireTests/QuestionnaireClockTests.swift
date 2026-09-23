//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveQuestionnaire
@testable import GroveQuestionnaireFHIR
import ModelsR4
import Synchronization
import Testing


/// Time functions read the clock the caller states: the wall clock once per state of the answers while a participant
/// answers, `authored` in its offset for a stored response.
@Suite
struct QuestionnaireClockTests {
    /// 2026-01-01T07:30Z: still New Year's Eve at -08:00, already New Year's Day at +09:00.
    private static let instant = Date(timeIntervalSince1970: 1_767_252_600)
    private static let pacific = TimeZone(secondsFromGMT: -8 * 3600) ?? .gmt
    private static let tokyo = TimeZone(secondsFromGMT: 9 * 3600) ?? .gmt

    private static var source: ModelsR4.Questionnaire {
        var answered = ModelsR4.QuestionnaireItem(linkId: "answered".asFHIRStringPrimitive(), type: .init(.boolean))
        answered.text = "answered".asFHIRStringPrimitive()
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/clock".asFHIRURIPrimitive()
        questionnaire.version = "1.0.0".asFHIRStringPrimitive()
        questionnaire.item = [
            answered,
            calculated("new-year", .boolean, "today() = @2026-01-01"),
            calculated("asked-at", .dateTime, "now()")
        ]
        return questionnaire
    }

    private static func calculated(_ linkId: String, _ type: QuestionnaireItemType, _ expression: String) -> ModelsR4.QuestionnaireItem {
        var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(type))
        item.text = linkId.asFHIRStringPrimitive()
        item.readOnly = FHIRPrimitive(FHIRBool(true))
        item.extension = [
            Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
                value: .expression(ModelsR4.Expression(
                    expression: expression.asFHIRStringPrimitive(),
                    language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
                ))
            )
        ]
        return item
    }

    @Test
    func storedResponseReEvaluatesIdenticallyOnAnyDevice() throws {
        let questionnaire = try GroveQuestionnaire.Questionnaire(Self.source, clock: .fixed(at: Self.instant, in: Self.tokyo))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["answered"] = .init(value: .bool(true))
        #expect(responses.responses["new-year"].value == .bool(true), "answered in Tokyo, where it is New Year's Day")

        let exported = try ModelsR4.QuestionnaireResponse(responses, authored: Self.instant, authoredTimeZone: Self.pacific)
        let newYear = exported.item?.first { $0.linkId.value?.string == "new-year" }
        #expect(newYear?.answer?.first?.value == .boolean(FHIRPrimitive(FHIRBool(false))), "recomputed at authored")

        // The device's zone is pinned out of evaluation in FHIRPathClockTests; changing it here would reach every test
        // running beside this one.
        let evaluator = try PairExpressionEvaluator.fhirPath(questionnaire: ModelsR4.Questionnaire(questionnaire), response: exported)
        let check = "%resource.item.where(linkId = 'new-year').answer.value = (today() = @2026-01-01)"
        #expect(try evaluator.evaluate(check, path: "QuestionnaireResponse") == true)
        let reimported = try GroveQuestionnaire.Questionnaire(Self.source, clock: .authored(exported))
        let replayed = QuestionnaireResponses(questionnaire: reimported)
        replayed.responses["answered"] = .init(value: .bool(true))
        #expect(replayed.responses["new-year"].value == .bool(false))
    }

    @Test
    func liveClockMovesWithTheAnswers() throws {
        let reads = Mutex(0)
        let clock = QuestionnaireClock(timeZone: .gmt) {
            reads.withLock { count in
                count += 1
                return Self.instant.addingTimeInterval(TimeInterval(count * 60))
            }
        }
        let questionnaire = try GroveQuestionnaire.Questionnaire(Self.source, clock: clock)
        let engine = try #require(questionnaire.expressionEngine)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)

        responses.responses["answered"] = .init(value: .bool(true))
        let first = responses.responses["asked-at"].value
        _ = try engine.evaluateBoolean("now() = now()", scope: .questionnaire, in: responses)
        let settled = reads.withLock { $0 }
        _ = try engine.evaluateBoolean("now() = now()", scope: .questionnaire, in: responses)
        _ = try engine.evaluateBoolean("today() = today()", scope: .questionnaire, in: responses)
        #expect(reads.withLock { $0 } == settled, "the same answers read the clock once")

        responses.responses["answered"] = .init(value: .bool(false))
        #expect(reads.withLock { $0 } > settled, "a new state of the answers reads it again")
        #expect(responses.responses["asked-at"].value != first, "time moves on with the answers")
    }

    @Test
    func pairWithoutAnAuthoredOffsetIsRefused() throws {
        let questionnaire = try ModelsR4.Questionnaire(GroveQuestionnaire.Questionnaire(Self.source, clock: .fixed(at: Self.instant, in: .gmt)))
        var response = ModelsR4.QuestionnaireResponse(status: FHIRPrimitive(QuestionnaireResponseStatus.completed))
        #expect(throws: ContractError.missingAuthored) {
            try PairExpressionEvaluator.fhirPath(questionnaire: questionnaire, response: response)
        }
        response.authored = FHIRPrimitive(DateTime("2026-01-01"))
        #expect(throws: ContractError.authoredWithoutOffset) {
            try PairExpressionEvaluator.fhirPath(questionnaire: questionnaire, response: response)
        }
    }
}

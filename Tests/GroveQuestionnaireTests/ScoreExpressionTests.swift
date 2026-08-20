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
import Testing


@available(iOS 18, macOS 15, watchOS 11, *)
private enum Burden: String, ScoredOption {
    case light
    case moderate
    case severe

    static let system = URL(string: "https://example.org/fhir/CodeSystem/burden")

    var title: String {
        switch self {
        case .light: "Barely"
        case .moderate: "Somewhat"
        case .severe: "Severely"
        }
    }

    var score: Decimal {
        switch self {
        case .light: 0
        case .moderate: 1
        case .severe: 2
        }
    }
}


@Instrument
@available(iOS 18, macOS 15, watchOS 11, *)
private enum Burdens {
    static let work = ChoiceQuestion<Burden>("work", "Difficulty at work")
    static let home = ChoiceQuestion<Burden>("home", "Difficulty at home")
    static let note = TextQuestion("note", "Anything else?").optional()
    static let total = NumberQuestion("total", "Total")
        .calculated(.sumOfWeights(of: work, home))
        .readOnly()
        .hidden()
        .optional()
    static let answered = NumberQuestion("answered", "Answered")
        .calculated(.countAnswered(of: work, home))
        .readOnly()
        .hidden()
        .optional()

    static let questionnaire = GroveQuestionnaire.Questionnaire(
        url: URL(string: "https://example.org/fhir/Questionnaire/burdens")!,
        version: "1.0.0",
        title: "Burdens"
    ) {
        Section("burden", title: "Burden") {
            work
            home
            note
            total
            answered
        }
    }
}


/// The emitted FHIRPath is a runtime contract between the DSL and the expression engine,
/// so both halves are pinned: the exact string, and what it evaluates to.
@Suite
struct ScoreExpressionTests {
    @Test
    func expressionsEmitTheirFHIRPath() {
        #expect(ScoreExpression.sumOfAllWeights.fhirPath == "%resource.descendants().valueCoding.weight().sum()")
        #expect(ScoreExpression.sumOfWeights(of: Burdens.work, Burdens.home).fhirPath == """
            %resource.descendants().where(linkId='work' or linkId='home').answer.valueCoding.weight().sum()
            """)
        #expect(ScoreExpression.countAnswered(of: Burdens.work).fhirPath == """
            %resource.descendants().where(linkId='work').answer.count()
            """)
        #expect(ScoreExpression.constant(3).fhirPath == "3")
        #expect(ScoreExpression.raw("1 + 1").fhirPath == "1 + 1")
        #expect((ScoreExpression.constant(1) + .constant(2)).fhirPath == "(1) + (2)")
        #expect((ScoreExpression.constant(4) / .constant(2)).fhirPath == "(4) / (2)")
    }

    /// A linkId carrying an apostrophe would otherwise close the `where` clause's string.
    @Test
    func quotesInLinkIDsAreEscaped() {
        let question = ChoiceQuestion<Burden>("it's", "Odd id")
        #expect(ScoreExpression.countAnswered(of: question).fhirPath.contains(#"linkId='it\'s'"#))
    }

    @Test
    func multiChoiceQuestionsCanBeScored() {
        let question = MultiChoiceQuestion<Burden>("many", "Which apply?")
        #expect(ScoreExpression.sumOfWeights(of: question).fhirPath.contains("linkId='many'"))
    }

    /// The score has to survive the trip through FHIR and back, because that is the path a
    /// participant's answers actually take.
    @Test
    func scoresEvaluateAgainstRealResponses() throws {
        let fhir = try ModelsR4.Questionnaire(Burdens.questionnaire)
        let reimported = try GroveQuestionnaire.Questionnaire(fhir, evaluationInstant: questionnaireResponseTestAuthoredAt)
        let responses = QuestionnaireResponses(questionnaire: reimported)
        let system = try #require(Burden.system?.absoluteString)

        responses.responses["work"] = .init(value: .choice(.init(selectedOptions: ["\(system)|severe"])))
        responses.responses["home"] = .init(value: .choice(.init(selectedOptions: ["\(system)|moderate"])))

        #expect(responses.responses["total"].value == .number(3))
        #expect(responses.responses["answered"].value == .number(2))
    }

    /// `.sumOfWeights(of:)` names the questions, so a question that no longer exists is a
    /// compile error rather than a score that quietly reads zero. These do not compile:
    ///
    /// ```swift
    /// .calculated(.sumOfWeights(of: Burdens.note))     // TextQuestion is not a ScoredQuestion
    /// .calculated(.sumOfWeights(of: unweighted))       // Option does not conform to ScoredOption
    /// .calculated(.sumOfWeights())                     // no questions to sum
    /// .calculated("%resource.descendants()…")          // unavailable: use .raw(…)
    /// ```
    @Test
    func scoredQuestionsCarryWeights() throws {
        let fhir = try ModelsR4.Questionnaire(Burdens.questionnaire)

        func find(_ linkId: String, _ items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.QuestionnaireItem? {
            for item in items {
                if item.linkId.value?.string == linkId {
                    return item
                }
                if let match = find(linkId, item.item ?? []) {
                    return match
                }
            }
            return nil
        }

        let work = try #require(find("work", fhir.item ?? []))
        let codings = try #require(work.answerOption).compactMap { option -> Coding? in
            guard case .coding(let coding) = option.value else {
                return nil
            }
            return coding
        }
        let weighted = codings.map { !$0.extensions(for: "http://hl7.org/fhir/StructureDefinition/itemWeight").isEmpty }
        #expect(weighted == [true, true, true])
    }
}

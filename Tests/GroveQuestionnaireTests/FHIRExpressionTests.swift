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


/// Covers the SDC expression features: enableWhenExpression, calculatedExpression,
/// variable, launchContext + initialExpression, and targetConstraint.
@Suite
struct FHIRExpressionTests {
    private func fhirPath(_ expression: String) -> ModelsR4.Expression {
        ModelsR4.Expression(
            expression: expression.asFHIRStringPrimitive(),
            language: FHIRPrimitive(ModelsR4.FHIRString("text/fhirpath"))
        )
    }

    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/expressions".asFHIRURIPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    private func weightedChoice(_ linkId: String) -> ModelsR4.QuestionnaireItem {
        func option(_ code: String, _ weight: Double) -> QuestionnaireItemAnswerOption {
            var coding = Coding(
                code: code.asFHIRStringPrimitive(),
                display: code.asFHIRStringPrimitive(),
                system: "https://example.org/scale".asFHIRURIPrimitive()
            )
            coding.extension = [
                Extension(
                url: "http://hl7.org/fhir/StructureDefinition/itemWeight",
                value: .decimal(FHIRPrimitive(FHIRDecimal(Decimal(weight))))
            )
            ]
            return QuestionnaireItemAnswerOption(value: .coding(coding))
        }
        var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.choice))
        item.text = linkId.asFHIRStringPrimitive()
        item.answerOption = [option("not-at-all", 0), option("several-days", 1), option("nearly-every-day", 3)]
        return item
    }

    // MARK: enableWhenExpression

    @Test
    func enableWhenExpressionDrivesEnablement() throws {
        var age = ModelsR4.QuestionnaireItem(linkId: "age".asFHIRStringPrimitive(), type: .init(.integer))
        age.text = "age".asFHIRStringPrimitive()
        var followUp = ModelsR4.QuestionnaireItem(linkId: "adult-only".asFHIRStringPrimitive(), type: .init(.boolean))
        followUp.text = "adult-only".asFHIRStringPrimitive()
        followUp.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
            value: .expression(fhirPath("%resource.item.where(linkId = 'age').answer.value.first() >= 18"))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [age, followUp]))
        #expect(questionnaire.expressionEngine != nil)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let target = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "adult-only" })
        #expect(!responses.shouldEnable(task: target), "unanswered source must disable the item")
        responses.responses["age"] = .init(value: .number(21))
        #expect(responses.shouldEnable(task: target))
        responses.responses["age"] = .init(value: .number(15))
        #expect(!responses.shouldEnable(task: target))
    }

    // MARK: calculatedExpression

    @Test
    func calculatedExpressionComputesScore() throws {
        var total = ModelsR4.QuestionnaireItem(linkId: "total".asFHIRStringPrimitive(), type: .init(.decimal))
        total.text = "total".asFHIRStringPrimitive()
        total.readOnly = FHIRPrimitive(FHIRBool(true))
        total.extension = [
            Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression",
                value: .expression(fhirPath("%resource.item.answer.weight().sum()"))
            ),
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden",
                value: .boolean(FHIRPrimitive(FHIRBool(true)))
            )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            weightedChoice("q1"), weightedChoice("q2"), total
        ]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["q1"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/scale|several-days"])))
        responses.responses["q2"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/scale|nearly-every-day"])))
        #expect(responses.responses["total"].value == .number(4))
        // The hidden score item flows into the emitted response.
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        let totalItem = fhirResponse.item?.first { $0.linkId.value?.string == "total" }
        #expect(totalItem?.answer?.first?.value == .decimal(FHIRPrimitive(FHIRDecimal(4))))
    }

    // MARK: variable

    @Test
    func variablesFeedExpressions() throws {
        var flagged = ModelsR4.QuestionnaireItem(linkId: "flagged".asFHIRStringPrimitive(), type: .init(.boolean))
        flagged.text = "flagged".asFHIRStringPrimitive()
        flagged.extension = [
            Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
                value: .expression(fhirPath("%score >= 2"))
            )
        ]
        var questionnaire = makeQuestionnaire(items: [weightedChoice("q1"), flagged])
        var scoreVariable = fhirPath("%resource.item.answer.weight().sum()")
        scoreVariable.name = FHIRPrimitive(ModelsR4.FHIRString("score"))
        questionnaire.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/variable",
            value: .expression(scoreVariable)
        )
        ]
        let converted = try GroveQuestionnaire.Questionnaire(questionnaire)
        let responses = QuestionnaireResponses(questionnaire: converted)
        let target = try #require(converted.sections.flatMap(\.tasks).first { $0.id == "flagged" })
        responses.responses["q1"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/scale|several-days"])))
        #expect(!responses.shouldEnable(task: target))
        responses.responses["q1"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/scale|nearly-every-day"])))
        #expect(responses.shouldEnable(task: target))

        let exported = try ModelsR4.Questionnaire(converted)
        guard case .expression(let expression)? = exported.extensions(
            for: "http://hl7.org/fhir/StructureDefinition/variable"
        ).first?.value else {
            Issue.record("Expected the questionnaire variable to survive export")
            return
        }
        #expect(expression.name?.value?.string == "score")
        #expect(expression.expression?.value?.string == "%resource.item.answer.weight().sum()")
    }

    // MARK: launchContext + initialExpression

    @Test
    func initialExpressionPopulatesFromLaunchContext() throws {
        var name = ModelsR4.QuestionnaireItem(linkId: "name".asFHIRStringPrimitive(), type: .init(.string))
        name.text = "name".asFHIRStringPrimitive()
        name.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression",
            value: .expression(fhirPath("%patient.name.first().given.first()"))
        )
        ]
        var patient = Patient()
        patient.name = [HumanName(family: "Lovelace".asFHIRStringPrimitive(), given: ["Ada".asFHIRStringPrimitive()])]
        let questionnaire = try GroveQuestionnaire.Questionnaire(
            makeQuestionnaire(items: [name]),
            using: .init(launchContext: ["patient": ResourceProxy(with: patient)])
        )
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(responses.responses["name"].value == .string("Ada"))

        let exported = try ModelsR4.Questionnaire(questionnaire)
        let exportedName = try #require(exported.item?.first)
        guard case .expression(let expression)? = exportedName.extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-initialExpression"
        ).first?.value else {
            Issue.record("Expected initialExpression to survive export")
            return
        }
        #expect(expression.expression?.value?.string == "%patient.name.first().given.first()")
        #expect(exportedName.initial == nil, "an evaluated initialExpression must not become a static initial value")
    }

    // MARK: targetConstraint

    @Test
    func targetConstraintValidatesWithAuthoredMessage() throws {
        var count = ModelsR4.QuestionnaireItem(linkId: "drinks".asFHIRStringPrimitive(), type: .init(.integer))
        count.text = "drinks".asFHIRStringPrimitive()
        var constraint = Extension(url: "http://hl7.org/fhir/StructureDefinition/targetConstraint")
        constraint.extension = [
            Extension(url: "expression", value: .expression(fhirPath(
                "%resource.item.where(linkId = 'drinks').answer.value.first() <= 50"
            ))),
            Extension(url: "human", value: .string(FHIRPrimitive(ModelsR4.FHIRString("Please enter a plausible number of drinks per week."))))
        ]
        count.extension = [constraint]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [count]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        responses.responses["drinks"] = .init(value: .number(12))
        #expect(responses.validateResponse(for: task).isOk)
        responses.responses["drinks"] = .init(value: .number(400))
        guard case .invalid(let message) = responses.validateResponse(for: task) else {
            Issue.record("Expected the constraint to reject the value")
            return
        }
        #expect(String(localized: message).contains("plausible number"))
    }

    // MARK: Runtime failures

    @Test
    func failingExpressionsAreRecordedRatherThanReadAsFalse() throws {
        var flagged = ModelsR4.QuestionnaireItem(linkId: "flagged".asFHIRStringPrimitive(), type: .init(.boolean))
        flagged.text = "flagged".asFHIRStringPrimitive()
        flagged.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
            value: .expression(fhirPath("%resource.item.notAFunction()"))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [flagged]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        // The item still disappears — but the reason is recoverable rather than lost.
        #expect(!responses.shouldEnable(task: task))
        let failure = try #require(responses.expressionFailures.first)
        #expect(failure.taskId == "flagged")
        #expect(failure.expression == "%resource.item.notAFunction()")
        _ = responses.shouldEnable(task: task)
        #expect(responses.expressionFailures.count == 1, "each failing expression is recorded once")
    }

    @Test
    func failingConstraintsAreRecordedAndLeaveTheAnswerValid() throws {
        var count = ModelsR4.QuestionnaireItem(linkId: "drinks".asFHIRStringPrimitive(), type: .init(.integer))
        count.text = "drinks".asFHIRStringPrimitive()
        var constraint = Extension(url: "http://hl7.org/fhir/StructureDefinition/targetConstraint")
        constraint.extension = [
            Extension(url: "expression", value: .expression(fhirPath("$this.notAFunction()"))),
            Extension(url: "human", value: .string(FHIRPrimitive(ModelsR4.FHIRString("Unreachable."))))
        ]
        count.extension = [constraint]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [count]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        responses.responses["drinks"] = .init(value: .number(12))
        // A rule that cannot be evaluated proves nothing, so the answer stands.
        #expect(responses.validateResponse(for: task).isOk)
        #expect(responses.expressionFailures.map(\.expression) == ["$this.notAFunction()"])
    }

    // MARK: Language guard

    @Test
    func nonFHIRPathExpressionLanguageIsRejected() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "q1".asFHIRStringPrimitive()
        item.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-enableWhenExpression",
            value: .expression(ModelsR4.Expression(
                expression: "AgeInYears() >= 18".asFHIRStringPrimitive(),
                language: FHIRPrimitive(ModelsR4.FHIRString("text/cql"))
            ))
        )
        ]
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        }
    }
}

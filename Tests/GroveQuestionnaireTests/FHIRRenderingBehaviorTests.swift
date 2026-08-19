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


/// Covers the rendering/behavior features: prefix, shortText, itemMedia, markdown,
/// supportLink, styleSensitive, keyboard hints, entryMode, quantity bounds, usageMode.
@Suite
struct FHIRRenderingBehaviorTests {
    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/rendering".asFHIRURIPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    private func firstTask(_ questionnaire: GroveQuestionnaire.Questionnaire) throws -> GroveQuestionnaire.Questionnaire.Task {
        try #require(questionnaire.sections.flatMap(\.tasks).first)
    }

    private func shortTextExtension(_ value: String) -> Extension {
        Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText",
            value: .string(value.asFHIRStringPrimitive())
        )
    }

    private func shortText(of item: ModelsR4.QuestionnaireItem) -> String? {
        guard case .string(let short)? = item.extensions(
            for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText"
        ).first?.value else {
            return nil
        }
        return short.value?.string
    }

    @Test
    func prefixAndShortTextAreParsed() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "Do you currently smoke tobacco products?".asFHIRStringPrimitive()
        item.prefix = "2a.".asFHIRStringPrimitive()
        item.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-shortText",
            value: .string(FHIRPrimitive(ModelsR4.FHIRString("Smoke?")))
        )
        ]
        let task = try firstTask(try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item])))
        #expect(task.prefix == "2a.")
        #expect(task.shortTitle == "Smoke?")
    }

    @Test
    func groupAndSectionShortTextSurviveTheRoundTrip() throws {
        var question = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        question.text = "Do you currently smoke tobacco products?".asFHIRStringPrimitive()
        var group = ModelsR4.QuestionnaireItem(linkId: "habits".asFHIRStringPrimitive(), type: .init(.group))
        group.text = "Habits that may affect your recovery".asFHIRStringPrimitive()
        group.extension = [shortTextExtension("Habits")]
        group.item = [question]
        var section = ModelsR4.QuestionnaireItem(linkId: "history".asFHIRStringPrimitive(), type: .init(.group))
        section.text = "Your medical and social history".asFHIRStringPrimitive()
        section.extension = [shortTextExtension("History")]
        section.item = [group]

        let imported = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [section]))
        #expect(imported.sections.first?.shortTitle == "History")
        let task = try firstTask(imported)
        #expect(task.groupPath.first?.shortTitle == "Habits")

        let exported = try ModelsR4.Questionnaire(imported)
        let exportedSection = try #require(exported.item?.first)
        let exportedGroup = try #require(exportedSection.item?.first)
        #expect(shortText(of: exportedSection) == "History")
        #expect(shortText(of: exportedGroup) == "Habits")
    }

    @Test
    func itemMediaIsParsedWithAltText() throws {
        let pixel = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic; content is irrelevant to parsing
        var attachment = Attachment()
        attachment.data = FHIRPrimitive(Base64Binary(pixel.base64EncodedString()))
        attachment.contentType = FHIRPrimitive(ModelsR4.FHIRString("image/png"))
        attachment.title = "Anatomical diagram of the shoulder".asFHIRStringPrimitive()
        var item = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "Does your pain match the highlighted area?".asFHIRStringPrimitive()
        item.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-itemMedia",
            value: .attachment(attachment)
        )
        ]
        let task = try firstTask(try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item])))
        #expect(task.media?.contentType == "image/png")
        #expect(task.media?.data == pixel)
        #expect(task.media?.altText == "Anatomical diagram of the shoulder")
    }

    @Test
    func renderingMarkdownIsPreferredForDisplayItems() throws {
        var text = FHIRPrimitive(ModelsR4.FHIRString("Important: do not eat before the test."))
        text.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/rendering-markdown",
            value: .markdown(FHIRPrimitive(ModelsR4.FHIRString("**Important:** do *not* eat before the test.")))
        )
        ]
        var item = ModelsR4.QuestionnaireItem(linkId: "d1".asFHIRStringPrimitive(), type: .init(.display))
        item.text = text
        let task = try firstTask(try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item])))
        guard case .instructional(let rendered) = task.kind.variant else {
            Issue.record("Expected an instructional task")
            return
        }
        #expect(rendered == "**Important:** do *not* eat before the test.")
    }

    @Test
    func supportLinkBecomesFooterLink() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = "Have you been diagnosed with hypertension?".asFHIRStringPrimitive()
        item.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-supportLink",
            value: .uri("https://example.org/what-is-hypertension")
        )
        ]
        let task = try firstTask(try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item])))
        #expect(task.footer.contains("https://example.org/what-is-hypertension"))
    }

    @Test
    func styleSensitiveSurfacesAWarning() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ])
        fhirQuestionnaire.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/rendering-styleSensitive",
            value: .boolean(FHIRPrimitive(FHIRBool(true)))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        #expect(questionnaire.metadata.administrationWarnings.contains { $0.contains("style-sensitive") })
    }

    @Test
    func keyboardHintIsParsed() throws {
        var email = ModelsR4.QuestionnaireItem(linkId: "email".asFHIRStringPrimitive(), type: .init(.string))
        email.text = "email".asFHIRStringPrimitive()
        email.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-keyboard",
            value: .codeableConcept(CodeableConcept(coding: [Coding(code: "email".asFHIRStringPrimitive())]))
        )
        ]
        let task = try firstTask(try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [email])))
        guard case .freeText(let config) = task.kind.variant else {
            Issue.record("Expected a free-text task")
            return
        }
        #expect(config.keyboard == .email)
    }

    @Test
    func entryModeIsParsed() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ])
        fhirQuestionnaire.extension = [
            Extension(
            url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-entryMode",
            value: .code(FHIRPrimitive(ModelsR4.FHIRString("sequential")))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        #expect(questionnaire.metadata.entryMode == .sequential)
    }

    @Test
    func quantityBoundsAreEnforced() throws {
        var weight = ModelsR4.QuestionnaireItem(linkId: "weight".asFHIRStringPrimitive(), type: .init(.quantity))
        weight.text = "weight".asFHIRStringPrimitive()
        weight.extension = [
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unit",
                value: .coding(Coding(
                    code: "kg".asFHIRStringPrimitive(),
                    display: "kg".asFHIRStringPrimitive(),
                    system: "http://unitsofmeasure.org".asFHIRURIPrimitive()
                ))
            ),
            Extension(
                url: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-maxQuantity",
                value: .quantity(Quantity(
                    code: "kg".asFHIRStringPrimitive(),
                    system: "http://unitsofmeasure.org".asFHIRURIPrimitive(),
                    value: FHIRPrimitive(FHIRDecimal(500))
                ))
            )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [weight]))
        let task = try firstTask(questionnaire)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(9_000))
        #expect(responses.validateResponse(for: task).isInvalid)
        responses.responses["weight"] = .init(value: .number(80))
        #expect(responses.validateResponse(for: task).isOk)
    }

    @Test
    func displayOnlyUsageModeHidesItemDuringCapture() throws {
        var reviewNote = ModelsR4.QuestionnaireItem(linkId: "review-note".asFHIRStringPrimitive(), type: .init(.display))
        reviewNote.text = "Reviewed by study staff.".asFHIRStringPrimitive()
        reviewNote.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-usageMode",
            value: .code(FHIRPrimitive(ModelsR4.FHIRString("display")))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            reviewNote,
            ModelsR4.QuestionnaireItem(linkId: "q1".asFHIRStringPrimitive(), text: "q1".asFHIRStringPrimitive(), type: .init(.boolean))
        ]))
        let tasks = questionnaire.sections.flatMap(\.tasks)
        #expect(tasks.first { $0.id == "review-note" }?.isHidden == true)
        #expect(tasks.first { $0.id == "q1" }?.isHidden == false)
    }
}

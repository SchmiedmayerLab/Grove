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


/// Verifies the behaviours required by FHIR R4 / SDC questionnaire semantics,
/// one test per audited conformance item.
@Suite
struct FHIRConformanceTests {
    // MARK: Helpers

    private func makeQuestionnaire(items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.Questionnaire {
        var questionnaire = ModelsR4.Questionnaire(status: FHIRPrimitive(PublicationStatus.active))
        questionnaire.url = "https://example.org/fhir/Questionnaire/conformance".asFHIRURIPrimitive()
        questionnaire.item = items
        return questionnaire
    }

    private func booleanItem(
        _ linkId: String,
        required: Bool = false,
        enableWhen: [QuestionnaireItemEnableWhen] = []
    ) -> ModelsR4.QuestionnaireItem {
        var item = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.boolean))
        item.text = linkId.asFHIRStringPrimitive()
        if required {
            item.required = FHIRPrimitive(FHIRBool(required))
        }
        item.enableWhen = enableWhen.isEmpty ? nil : enableWhen
        return item
    }

    private func groupItem(_ linkId: String, _ items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.QuestionnaireItem {
        var group = ModelsR4.QuestionnaireItem(linkId: linkId.asFHIRStringPrimitive(), type: .init(.group))
        group.item = items
        return group
    }

    /// The exported item with the given linkId, at any depth.
    private func item(_ linkId: String, in questionnaire: ModelsR4.Questionnaire) -> ModelsR4.QuestionnaireItem? {
        func find(_ items: [ModelsR4.QuestionnaireItem]) -> ModelsR4.QuestionnaireItem? {
            for item in items {
                if item.linkId.value?.string == linkId {
                    return item
                }
                if let match = find(item.item ?? []) {
                    return match
                }
            }
            return nil
        }
        return find(questionnaire.item ?? [])
    }

    // MARK: A1 — `required` defaults to false

    @Test
    func requiredDefaultsToOptional() throws {
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            booleanItem("q1"),
            booleanItem("q2", required: true)
        ]))
        let tasks = questionnaire.sections.flatMap(\.tasks)
        #expect(tasks.first { $0.id == "q1" }?.isOptional == true)
        #expect(tasks.first { $0.id == "q2" }?.isOptional == false)
    }

    // MARK: A2 — `!=` is false while the source is unanswered

    @Test
    func notEqualIsFalseWhenSourceUnanswered() throws {
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .boolean(FHIRPrimitive(FHIRBool(true))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.notEqual),
            question: "q1".asFHIRStringPrimitive()
        )
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            booleanItem("q1"),
            booleanItem("q2", enableWhen: [enableWhen])
        ]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let target = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "q2" })
        // Unanswered source: != must NOT enable the target.
        #expect(!responses.shouldEnable(task: target))
        // Equal answer: still disabled.
        responses.responses["q1"] = .init(value: .bool(true))
        #expect(!responses.shouldEnable(task: target))
        // Different answer: enabled.
        responses.responses["q1"] = .init(value: .bool(false))
        #expect(responses.shouldEnable(task: target))
    }

    // MARK: A3 — coding matching honors the system

    @Test
    func enableWhenCodingMatchingHonorsSystem() throws {
        func option(_ system: String, _ code: String) -> QuestionnaireItemAnswerOption {
            .init(value: .coding(Coding(
                code: code.asFHIRStringPrimitive(),
                display: code.asFHIRStringPrimitive(),
                system: system.asFHIRURIPrimitive()
            )))
        }
        var choice = ModelsR4.QuestionnaireItem(linkId: "c1".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "pick".asFHIRStringPrimitive()
        choice.answerOption = [
            option("https://example.org/system-a", "shared-code"),
            option("https://example.org/system-b", "shared-code")
        ]
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .coding(Coding(
                code: "shared-code".asFHIRStringPrimitive(),
                system: "https://example.org/system-b".asFHIRURIPrimitive()
            )),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: "c1".asFHIRStringPrimitive()
        )
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            choice,
            booleanItem("q2", enableWhen: [enableWhen])
        ]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let target = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "q2" })
        // Selecting the same code from system A must NOT satisfy a system-B condition.
        responses.responses["c1"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/system-a|shared-code"])))
        #expect(!responses.shouldEnable(task: target))
        // Selecting it from system B satisfies the condition.
        responses.responses["c1"] = .init(value: .choice(.init(selectedOptions: ["https://example.org/system-b|shared-code"])))
        #expect(responses.shouldEnable(task: target))
    }

    // MARK: A12 — forward references resolve

    @Test
    func forwardReferencesResolve() throws {
        let enableWhen = QuestionnaireItemEnableWhen(
            answer: .boolean(FHIRPrimitive(FHIRBool(true))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: "later".asFHIRStringPrimitive()
        )
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            booleanItem("early", enableWhen: [enableWhen]),
            booleanItem("later")
        ]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let early = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "early" })
        #expect(!responses.shouldEnable(task: early))
        responses.responses["later"] = .init(value: .bool(true))
        #expect(responses.shouldEnable(task: early))
    }

    // MARK: A11 — answers of a disabled item are treated as absent

    @Test
    func disabledSourceAnswersAreAbsent() throws {
        // target is enabled iff q1 == true; target is enabled iff target == true.
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            booleanItem("q1"),
            booleanItem("q2", enableWhen: [
                .init(
                answer: .boolean(FHIRPrimitive(FHIRBool(true))),
                operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
                question: "q1".asFHIRStringPrimitive()
            )
            ]),
            booleanItem("q3", enableWhen: [
                .init(
                answer: .boolean(FHIRPrimitive(FHIRBool(true))),
                operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
                question: "q2".asFHIRStringPrimitive()
            )
            ])
        ]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let target = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "q3" })
        // Answer target while it is enabled...
        responses.responses["q1"] = .init(value: .bool(true))
        responses.responses["q2"] = .init(value: .bool(true))
        #expect(responses.shouldEnable(task: target))
        // ...then flip q1, disabling target: its stored answer must stop driving target.
        responses.responses["q1"] = .init(value: .bool(false))
        #expect(!responses.shouldEnable(task: target))
    }

    // MARK: A7 — unknown itemControl codes fall back to the standard widget

    @Test
    func unknownItemControlFallsBack() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "s1".asFHIRStringPrimitive(), type: .init(.string))
        item.text = "name".asFHIRStringPrimitive()
        item.extension = [
            Extension(
                url: "http://hl7.org/fhir/StructureDefinition/questionnaire-itemControl",
                value: .codeableConcept(CodeableConcept(coding: [
                    Coding(
                        code: "autocomplete".asFHIRStringPrimitive(),
                        system: "http://hl7.org/fhir/questionnaire-item-control"
                    )
                ]))
            )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        guard case .freeText = task.kind.variant else {
            Issue.record("Expected fallback to the standard free-text widget, got \(task.kind.variant)")
            return
        }
    }

    // MARK: A5/A6 — integer and url answer types

    @Test
    func integerItemEmitsValueInteger() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "count".asFHIRStringPrimitive(), type: .init(.integer))
        item.text = "how many".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["count"] = .init(value: .number(3))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        let answer = try #require(exported.item?.first?.answer?.first)
        guard case .integer(let value) = try #require(answer.value) else {
            Issue.record("Expected valueInteger, got \(String(describing: answer.value))")
            return
        }
        #expect(value.value?.integer == 3)
    }

    @Test
    func urlItemEmitsValueUri() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "website".asFHIRStringPrimitive(), type: .init(.url))
        item.text = "your website".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["website"] = .init(value: .string("https://example.org"))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        let answer = try #require(exported.item?.first?.answer?.first)
        guard case .uri = try #require(answer.value) else {
            Issue.record("Expected valueUri, got \(String(describing: answer.value))")
            return
        }
    }

    // MARK: A10 — quantity answers keep the coded unit

    @Test
    func quantityAnswerCarriesCodedUnit() throws {
        var item = ModelsR4.QuestionnaireItem(linkId: "weight".asFHIRStringPrimitive(), type: .init(.quantity))
        item.text = "your weight".asFHIRStringPrimitive()
        item.extension = [
            Extension(
            url: "http://hl7.org/fhir/StructureDefinition/questionnaire-unitOption",
            value: .coding(Coding(
                code: "kg".asFHIRStringPrimitive(),
                display: "kilogram".asFHIRStringPrimitive(),
                system: "http://unitsofmeasure.org".asFHIRURIPrimitive()
            ))
        )
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["weight"] = .init(value: .number(72.5))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        let answer = try #require(exported.item?.first?.answer?.first)
        guard case .quantity(let quantity) = try #require(answer.value) else {
            Issue.record("Expected valueQuantity, got \(String(describing: answer.value))")
            return
        }
        #expect(quantity.code?.value?.string == "kg")
        #expect(quantity.system?.value?.url.absoluteString == "http://unitsofmeasure.org")
        #expect(quantity.unit?.value?.string == "kilogram")
    }

    // MARK: A9 — the response mirrors the questionnaire's structure

    @Test
    func responseMirrorsGroupHierarchy() throws {
        let inner = booleanItem("inner-q")
        var nestedGroup = ModelsR4.QuestionnaireItem(linkId: "nested-group".asFHIRStringPrimitive(), type: .init(.group))
        nestedGroup.item = [inner]
        var topGroup = ModelsR4.QuestionnaireItem(linkId: "top-group".asFHIRStringPrimitive(), type: .init(.group))
        topGroup.item = [booleanItem("outer-q"), nestedGroup]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [topGroup]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["outer-q"] = .init(value: .bool(true))
        responses.responses["inner-q"] = .init(value: .bool(false))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        // top-group wraps everything; nested-group wraps inner-q.
        let top = try #require(exported.item?.first)
        #expect(top.linkId.value?.string == "top-group")
        #expect(top.item?.count == 2)
        #expect(top.item?.first?.linkId.value?.string == "outer-q")
        let nested = try #require(top.item?.last)
        #expect(nested.linkId.value?.string == "nested-group")
        #expect(nested.item?.first?.linkId.value?.string == "inner-q")
    }

    @Test
    func responseNestsChildQuestionsUnderParentAnswer() throws {
        let child = booleanItem("child-q")
        var parent = booleanItem("parent-q")
        parent.item = [child]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [parent]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["parent-q"] = .init(value: .bool(true))
        responses.responses["child-q"] = .init(value: .bool(false))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        let parentItem = try #require(exported.item?.first)
        #expect(parentItem.linkId.value?.string == "parent-q")
        // The child's answer lives beneath the parent's answer, mirroring the questionnaire.
        let childItem = try #require(parentItem.answer?.first?.item?.first)
        #expect(childItem.linkId.value?.string == "child-q")
    }

    @Test
    func childQuestionsRequireAnsweredParent() throws {
        let child = booleanItem("child-q")
        var parent = booleanItem("parent-q")
        parent.item = [child]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [parent]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let childTask = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "child-q" })
        // FHIR: a question nested beneath a question is only asked once the parent is answered.
        #expect(!responses.shouldEnable(task: childTask))
        responses.responses["parent-q"] = .init(value: .bool(true))
        #expect(responses.shouldEnable(task: childTask))
    }

    // MARK: A17 — duplicate linkIds are a catchable error

    @Test
    func duplicateLinkIdsThrow() throws {
        #expect(throws: GroveQuestionnaire.Questionnaire.FHIRConversionError.self) {
            try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
                booleanItem("dup"),
                booleanItem("dup")
            ]))
        }
    }

    // MARK: A14 — an unanswered response omits `item` entirely

    @Test
    func emptyResponseOmitsItemArray() throws {
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [booleanItem("q1")]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        #expect(exported.item == nil)
    }

    // MARK: Version-pinned canonical

    @Test
    func responsePinsQuestionnaireVersion() throws {
        var fhirQuestionnaire = makeQuestionnaire(items: [booleanItem("q1")])
        fhirQuestionnaire.version = "2.1.0".asFHIRStringPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(fhirQuestionnaire)
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["q1"] = .init(value: .bool(true))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        #expect(exported.questionnaire?.value?.version == "2.1.0")
        #expect(exported.questionnaire?.value?.url.absoluteString == "https://example.org/fhir/Questionnaire/conformance")
    }

    // MARK: readOnly

    @Test
    func readOnlyIsParsed() throws {
        var item = booleanItem("locked")
        item.readOnly = FHIRPrimitive(FHIRBool(true))
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [item]))
        #expect(questionnaire.sections.flatMap(\.tasks).first?.isReadOnly == true)
    }

    // MARK: que-1/6/8/9 — display items carry none of the answer-bearing elements

    @Test
    func displayItemsOmitElementsFHIRForbids() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/display")!,
            title: "Display"
        ) {
            Section("s1", title: "Section") {
                Instruction("intro", "Read this first.")
                    .help("Some guidance.")
                    .readOnly()
                BooleanQuestion("q1", "Understood?")
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let intro = try #require(item("intro", in: fhir))
        #expect(intro.type.value == .display)
        #expect(intro.required == nil)
        #expect(intro.readOnly == nil)
        #expect(intro.initial == nil)
        #expect(intro.item == nil)
        // The renderer's `required` default still reaches items that may carry it.
        #expect(item("q1", in: fhir)?.required?.value?.bool == true)
    }

    // MARK: que-11 — a pre-selected option is `initialSelected`, not `initial`

    @Test
    func choiceInitialValueIsWrittenAsInitialSelected() throws {
        let system = URL(string: "https://example.org/opts")
        let mood = DynamicChoiceQuestion("mood", "Mood", system: system, choices: [
            Choice("good", "Good"),
            Choice("bad", "Bad")
        ]).initialValue("bad")
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/preselect")!,
            title: "Preselect"
        ) {
            Section("s1") { mood }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let exported = try #require(item("mood", in: fhir))
        #expect(exported.initial == nil)
        #expect(exported.answerOption?.count == 2)
        #expect(exported.answerOption?.first?.initialSelected == nil)
        #expect(exported.answerOption?.last?.initialSelected?.value?.bool == true)
        // The reader takes the pre-selection back off the answerOption.
        let reimported = try GroveQuestionnaire.Questionnaire(fhir)
        let responses = QuestionnaireResponses(questionnaire: reimported)
        #expect(responses.responses["mood"].value.choiceValue.selectedOptions == ["https://example.org/opts|bad"])
    }

    // MARK: targetConstraint carries its mandatory key

    @Test
    func targetConstraintCarriesAKey() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/constraints")!,
            title: "Constraints"
        ) {
            Section("s1") {
                TextQuestion("email", "Email").constraint("$this.matches('.+@.+')", message: "Enter a valid address.")
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let email = try #require(item("email", in: fhir))
        let target = try #require(email.extensions(for: "http://hl7.org/fhir/StructureDefinition/targetConstraint").first)
        let key = target.extension?.first { $0.url.value?.url.absoluteString == "key" }
        guard case .id(let value)? = key?.value else {
            Issue.record("Expected a valueId key sub-extension, got \(String(describing: key?.value))")
            return
        }
        #expect(value.value?.string == "email-1")
        let reimported = try GroveQuestionnaire.Questionnaire(fhir)
        #expect(reimported.sections.flatMap(\.tasks).first?.constraints.first?.key == "email-1")
    }

    // MARK: qty-3 — a coded Quantity carries its system

    @Test
    func exportedQuantitiesCarryTheirUnitSystem() throws {
        let ucum = URL(string: "http://unitsofmeasure.org")
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(
                id: "units",
                url: URL(string: "https://example.org/fhir/Questionnaire/units"),
                title: "Units",
                explainer: ""
            ),
            sections: [
                .init(
                    id: "s1",
                    tasks: [
                        .init(
                            id: "weight",
                            title: "Weight",
                            kind: .numeric(.init(
                                inputMode: .numberPad(.decimal),
                                unit: "kg",
                                unitSystem: ucum,
                                unitCode: "kg",
                                valueKind: .quantity
                            )),
                            initialValue: .quantity(70, unitCode: "kg")
                        ),
                        .init(
                            id: "heavy",
                            title: "Heavy?",
                            kind: .boolean,
                            enabledCondition: .responseValueComparison(
                                taskId: "weight",
                                operator: .greaterThan,
                                value: .quantity(value: 100, unitCode: "kg")
                            )
                        )
                    ],
                    fhirGroupId: "s1"
                )
            ]
        )
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        guard case .quantity(let initial)? = item("weight", in: fhir)?.initial?.first?.value else {
            Issue.record("Expected an initial quantity")
            return
        }
        #expect(initial.code?.value?.string == "kg")
        #expect(initial.system?.value?.url == ucum)
        guard case .quantity(let answer)? = item("heavy", in: fhir)?.enableWhen?.first?.answer else {
            Issue.record("Expected an enableWhen quantity")
            return
        }
        #expect(answer.code?.value?.string == "kg")
        #expect(answer.system?.value?.url == ucum)
    }

    // MARK: The SDC keyboard hint is a Coding in both directions

    @Test
    func keyboardHintIsACoding() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/keyboard")!,
            title: "Keyboard"
        ) {
            Section("s1") {
                TextQuestion("email", "Email").keyboard(.email)
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let keyboard = try #require(item("email", in: fhir))
            .extensions(for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-keyboard").first
        guard case .coding(let coding)? = keyboard?.value else {
            Issue.record("Expected a valueCoding, got \(String(describing: keyboard?.value))")
            return
        }
        #expect(coding.code?.value?.string == "email")
        #expect(coding.system?.value?.url.absoluteString == "http://hl7.org/fhir/uv/sdc/CodeSystem/keyboardType")
        let reimported = try GroveQuestionnaire.Questionnaire(fhir)
        guard case .freeText(let config) = try #require(reimported.sections.flatMap(\.tasks).first).kind.variant else {
            Issue.record("Expected a free-text task")
            return
        }
        #expect(config.keyboard == .email)
    }

    // MARK: item.code and item.definition survive the round trip

    @Test
    func itemCodeAndDefinitionRoundTrip() throws {
        var scored = booleanItem("phq9-1")
        scored.code = [
            Coding(
            code: "44250-9".asFHIRStringPrimitive(),
            display: "Little interest or pleasure in doing things".asFHIRStringPrimitive(),
            system: "http://loinc.org".asFHIRURIPrimitive()
        )
        ]
        scored.definition = "https://example.org/StructureDefinition/phq9#item".asFHIRURIPrimitive()
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [scored]))
        let task = try #require(questionnaire.sections.flatMap(\.tasks).first)
        #expect(task.codes == [
            .init(
            system: URL(string: "http://loinc.org"),
            code: "44250-9",
            display: "Little interest or pleasure in doing things"
        )
        ])
        #expect(task.definition?.absoluteString == "https://example.org/StructureDefinition/phq9#item")
        let exported = try ModelsR4.Questionnaire(questionnaire)
        let exportedItem = try #require(item("phq9-1", in: exported))
        #expect(exportedItem.code?.first?.code?.value?.string == "44250-9")
        #expect(exportedItem.code?.first?.system?.value?.url.absoluteString == "http://loinc.org")
        #expect(exportedItem.definition?.value?.url.absoluteString == "https://example.org/StructureDefinition/phq9#item")
    }

    // MARK: The export describes the same tree the response emitter does

    @Test
    func exportRestoresTheItemTree() throws {
        var parent = booleanItem("outer-q")
        parent.item = [booleanItem("child-q")]
        let top = groupItem("top-group", [parent, groupItem("nested-group", [booleanItem("inner-q")])])
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [top]))
        let exported = try ModelsR4.Questionnaire(questionnaire)
        let exportedTop = try #require(exported.item?.first)
        #expect(exportedTop.linkId.value?.string == "top-group")
        #expect(exportedTop.item?.map { $0.linkId.value?.string } == ["outer-q", "nested-group"])
        #expect(exportedTop.item?.first?.item?.map { $0.linkId.value?.string } == ["child-q"])
        #expect(exportedTop.item?.last?.item?.map { $0.linkId.value?.string } == ["inner-q"])
    }

    @Test
    func synthesizedWrapperGroupsAreNotReExported() throws {
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [
            booleanItem("q1"), booleanItem("q2")
        ]))
        #expect(questionnaire.sections.first?.fhirGroupId == nil, "the section wraps ungrouped items")
        let exported = try ModelsR4.Questionnaire(questionnaire)
        #expect(exported.item?.map { $0.linkId.value?.string } == ["q1", "q2"])
    }

    @Test
    func choiceFollowUpsExportAsNestedItems() throws {
        let system = try #require(URL(string: "https://example.org/opts"))
        let questionnaire = GroveQuestionnaire.Questionnaire(
            metadata: .init(
                id: "follow-ups",
                url: URL(string: "https://example.org/fhir/Questionnaire/follow-ups"),
                title: "Follow-ups",
                explainer: ""
            ),
            sections: [
                .init(
                    id: "s1",
                    tasks: [
                        .init(id: "pick", title: "Pick", kind: .choice(.init(
                            options: [
                                .init(id: "\(system.absoluteString)|a", title: "A", fhirCoding: .init(system: system, code: "a"))
                            ],
                            allowsMultipleSelection: false,
                            followUpTasks: [.init(id: "why", title: "Why?", kind: .freeText(.init()))]
                        )))
                    ],
                    fhirGroupId: "s1"
                )
            ]
        )
        let exported = try ModelsR4.Questionnaire(questionnaire)
        // FHIR asks items nested beneath a question once per answer — the follow-up's semantics.
        #expect(item("pick", in: exported)?.item?.map { $0.linkId.value?.string } == ["why"])
    }

    // MARK: String answerOptions

    @Test
    func stringAnswerOptionsRoundTrip() throws {
        var choice = ModelsR4.QuestionnaireItem(linkId: "flavor".asFHIRStringPrimitive(), type: .init(.choice))
        choice.text = "pick a flavor".asFHIRStringPrimitive()
        choice.answerOption = [
            .init(value: .string("Vanilla".asFHIRStringPrimitive())),
            .init(value: .string("Chocolate".asFHIRStringPrimitive()))
        ]
        let questionnaire = try GroveQuestionnaire.Questionnaire(makeQuestionnaire(items: [choice]))
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses.responses["flavor"] = .init(value: .choice(.init(selectedOptions: ["string|Vanilla"])))
        let exported = try ModelsR4.QuestionnaireResponse(responses)
        let answer = try #require(exported.item?.first?.answer?.first)
        guard case .string(let value) = try #require(answer.value) else {
            Issue.record("Expected valueString, got \(String(describing: answer.value))")
            return
        }
        #expect(value.value?.string == "Vanilla")
    }

    // MARK: Nested groups

    /// A nested group carries its own heading and its own `enableWhen`. Before the group
    /// became a modelled value, only its linkId survived the import, so the export
    /// rebuilt an untitled group and restated the condition on every child.
    @Test
    func nestedGroupsRoundTripTheirTitleAndCondition() throws {
        var inner = groupItem("mood-block", [booleanItem("down"), booleanItem("anhedonia")])
        inner.text = "Over the last two weeks".asFHIRStringPrimitive()
        var when = QuestionnaireItemEnableWhen(
            answer: .boolean(FHIRPrimitive(FHIRBool(true))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: "screener".asFHIRStringPrimitive()
        )
        when.answer = .boolean(FHIRPrimitive(FHIRBool(true)))
        inner.enableWhen = [when]
        let source = makeQuestionnaire(items: [groupItem("s1", [booleanItem("screener"), inner])])

        let grove = try GroveQuestionnaire.Questionnaire(source)
        let exported = try ModelsR4.Questionnaire(grove)

        let group = try #require(item("mood-block", in: exported))
        #expect(group.type.value == .group)
        #expect(group.text?.value?.string == "Over the last two weeks")
        #expect(group.enableWhen?.count == 1)
        #expect(group.enableWhen?.first?.question.value?.string == "screener")
        // The children sit under the group and no longer restate its condition.
        #expect(group.item?.compactMap { $0.linkId.value?.string } == ["down", "anhedonia"])
        #expect(item("down", in: exported)?.enableWhen == nil)
    }

    /// A task inside a disabled group is not asked. The import stopped copying the group's
    /// condition onto each child, so the renderer has to consult the group itself.
    @Test
    func aTaskInsideADisabledGroupIsDisabled() throws {
        var inner = groupItem("mood-block", [booleanItem("down")])
        var when = QuestionnaireItemEnableWhen(
            answer: .boolean(FHIRPrimitive(FHIRBool(true))),
            operator: FHIRPrimitive(QuestionnaireItemOperator.equal),
            question: "screener".asFHIRStringPrimitive()
        )
        when.answer = .boolean(FHIRPrimitive(FHIRBool(true)))
        inner.enableWhen = [when]
        let source = makeQuestionnaire(items: [groupItem("s1", [booleanItem("screener"), inner])])
        let questionnaire = try GroveQuestionnaire.Questionnaire(source)
        let down = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "down" })

        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        #expect(!responses.shouldEnable(task: down), "the group's condition is unmet")
        responses.responses["screener"] = .init(value: .bool(true))
        #expect(responses.shouldEnable(task: down), "the group's condition now holds")
    }
}

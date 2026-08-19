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


/// The PHQ answer frequency scale, declared once as a closed option set.
@available(iOS 18, macOS 15, watchOS 11, *)
private enum Frequency: String, ScoredOption {
    case notAtAll = "not-at-all"
    case severalDays = "several-days"
    case moreThanHalf = "more-than-half"
    case nearlyEveryDay = "nearly-every-day"

    static let system = URL(string: "https://example.org/fhir/CodeSystem/phq-scale")

    var title: String {
        switch self {
        case .notAtAll: "Not at all"
        case .severalDays: "Several days"
        case .moreThanHalf: "More than half the days"
        case .nearlyEveryDay: "Nearly every day"
        }
    }

    var score: Decimal {
        switch self {
        case .notAtAll: 0
        case .severalDays: 1
        case .moreThanHalf: 2
        case .nearlyEveryDay: 3
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private enum Activity: String, QuestionnaireOption {
    case running
    case cycling

    static let system = URL(string: "https://example.org/fhir/CodeSystem/activity")

    var title: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private enum Cadence: String, QuestionnaireOption {
    case daily
    case weekly

    static let system = URL(string: "https://example.org/fhir/CodeSystem/cadence")

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Once per week"
        }
    }
}


/// An instrument whose choice question carries follow-ups, asked once per selected activity.
@Instrument
@available(iOS 18, macOS 15, watchOS 11, *)
private enum ActivityLog {
    static let activities = MultiChoiceQuestion<Activity>("activities", "Which activities did you do?")
    static let cadence = ChoiceQuestion<Cadence>("cadence", "How often?")

    static let questionnaire = GroveQuestionnaire.Questionnaire(
        url: URL(string: "https://example.org/fhir/Questionnaire/activity-log")!,
        title: "Activity Log"
    ) {
        Section("log", title: "Your Week") {
            activities.followUp {
                cadence
                NumberQuestion.integer("minutes", "How many minutes each time?")
            }
        }
    }
}


/// A PHQ-2-style scored instrument declared with the Swift DSL, used across the tests.
@Instrument
@available(iOS 18, macOS 15, watchOS 11, *)
private enum CheckIn {
    static let interest = ChoiceQuestion<Frequency>("interest", "Little interest or pleasure in doing things")
        .prefix("1.")
    static let mood = ChoiceQuestion<Frequency>("mood", "Feeling down, depressed, or hopeless")
        .prefix("2.")
    static let total = NumberQuestion("total", "Score")
        .calculated(.sumOfAllWeights)
        .readOnly()
        .hidden()
        .optional()
    static let followUp = TextQuestion("follow-up", "What has been troubling you?")
        .enabledWhen(mood.selected(.nearlyEveryDay) || interest.selected(.nearlyEveryDay))
        .optional()
    static let consent = BooleanQuestion("consented", "I answered honestly")
        .initialValue(true)

    static let questionnaire = GroveQuestionnaire.Questionnaire(
        url: URL(string: "https://example.org/fhir/Questionnaire/check-in")!,
        version: "2.1.0",
        title: "Daily Check-In",
        explainer: "Two questions about the last two weeks."
    ) {
        Section("phq", title: "About the last two weeks") {
            Instruction("intro", "Over the **last two weeks**, how often have you been bothered by the following?")
            interest
            mood
            total
            followUp
            consent
        }
    }
}


@Suite
struct QuestionnaireDSLTests {
    @Test
    func dslBuildsTheModel() throws {
        let questionnaire = CheckIn.questionnaire
        #expect(questionnaire.metadata.version == "2.1.0")
        #expect(questionnaire.metadata.title == "Daily Check-In")
        let tasks = questionnaire.sections.flatMap(\.tasks)
        #expect(tasks.map(\.id) == ["intro", "interest", "mood", "total", "follow-up", "consented"])
        let interest = try #require(tasks.first { $0.id == "interest" })
        #expect(interest.prefix == "1.")
        #expect(!interest.isOptional)
        guard case .choice(let config) = interest.kind.variant else {
            Issue.record("Expected a choice task")
            return
        }
        #expect(config.options.count == 4)
        #expect(config.options.last?.weight == 3)
        let total = try #require(tasks.first { $0.id == "total" })
        #expect(total.isHidden && total.isReadOnly)
        #expect(total.calculatedExpression != nil)
        #expect(tasks.first { $0.id == "consented" }?.initialValue == .bool(true))
    }

    @Test
    func typedHandlesReadAndWriteResponses() throws {
        let responses = QuestionnaireResponses(questionnaire: CheckIn.questionnaire)
        // The initial value seeded the consent question.
        #expect(responses[CheckIn.consent] == true)
        responses[CheckIn.mood] = .nearlyEveryDay
        responses[CheckIn.followUp] = "Trouble sleeping."
        #expect(responses[CheckIn.mood] == .nearlyEveryDay)
        #expect(responses[CheckIn.followUp] == "Trouble sleeping.")
        #expect(responses[CheckIn.interest] == nil)
        // The option is stored as its `system|code` token, whatever the typed API takes.
        let system = try #require(Frequency.system?.absoluteString)
        #expect(responses.responses["mood"].value.choiceValue.selectedOptions == ["\(system)|nearly-every-day"])
    }

    @Test
    func typedChoiceAnswersExport() throws {
        let responses = QuestionnaireResponses(questionnaire: CheckIn.questionnaire)
        responses[CheckIn.mood] = .nearlyEveryDay
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        let mood = try #require(fhirResponse.item?.first?.item?.first { $0.linkId.value?.string == "mood" })
        guard case .coding(let coding)? = mood.answer?.first?.value else {
            Issue.record("Expected a coded answer, got \(String(describing: mood.answer?.first?.value))")
            return
        }
        #expect(coding.code?.value?.string == "nearly-every-day")
        #expect(coding.system?.value?.url == Frequency.system)
    }

    /// The option set the enum declares is the option set FHIR receives — same codes,
    /// same system, same order, same weights as the hand-listed options it replaced.
    @Test
    func declaredOptionsExportAsAnswerOptions() throws {
        let fhir = try ModelsR4.Questionnaire(CheckIn.questionnaire)
        let mood = try #require(fhir.item?.first?.item?.first { $0.linkId.value?.string == "mood" })
        let codings = try #require(mood.answerOption).compactMap { option -> Coding? in
            guard case .coding(let coding) = option.value else {
                return nil
            }
            return coding
        }
        #expect(codings.compactMap { $0.code?.value?.string } == ["not-at-all", "several-days", "more-than-half", "nearly-every-day"])
        #expect(codings.allSatisfy { $0.system?.value?.url == Frequency.system })
        #expect(codings.compactMap { $0.display?.value?.string }.first == "Not at all")
        let weights = codings.map { $0.extensions(for: "http://hl7.org/fhir/StructureDefinition/itemWeight") }
        #expect(weights.allSatisfy { !$0.isEmpty })
    }

    /// The typed condition has to be the very same condition the string-coded form builds,
    /// or a branch keyed on it would resolve against a different option token.
    @Test
    func typedAndCodedConditionsAgree() {
        let coded = DynamicChoiceQuestion("mood", "Mood", system: Frequency.system, choices: Frequency.allCases.map {
            Choice($0.rawValue, $0.title)
        })
        #expect(CheckIn.mood.selected(.nearlyEveryDay) == coded.selected("nearly-every-day"))
    }

    /// Options that only exist at runtime keep an unchecked, string-coded form.
    @Test
    func dynamicChoiceQuestionsStillWork() throws {
        let system = try #require(URL(string: "https://example.org/fhir/CodeSystem/resolved"))
        let resolved = ["red", "green"].map { Choice($0, $0.capitalized) }
        let colour = DynamicChoiceQuestion("colour", "Favourite colour", system: system, choices: resolved)
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/dynamic")),
            title: "Dynamic"
        ) {
            Section("s1") { colour }
        }
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        responses[colour] = "green"
        #expect(responses[colour] == "green")
        #expect(responses.responses["colour"].value.choiceValue.selectedOptions == ["\(system.absoluteString)|green"])
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let item = try #require(fhir.item?.first?.item?.first)
        #expect(item.answerOption?.count == 2)
    }

    @Test
    func booleanConditionsGateOnTheAnswer() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/boolean")),
            title: "Boolean"
        ) {
            Section("s1") {
                CheckIn.consent
                TextQuestion("why-not", "Why not?").enabledWhen(CheckIn.consent.isFalse).optional()
            }
        }
        let responses = QuestionnaireResponses(questionnaire: questionnaire)
        let whyNot = try #require(questionnaire.sections.flatMap(\.tasks).first { $0.id == "why-not" })
        #expect(!responses.shouldEnable(task: whyNot))
        responses[CheckIn.consent] = false
        #expect(responses.shouldEnable(task: whyNot))
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let exported = try #require(fhir.item?.first?.item?.first { $0.linkId.value?.string == "why-not" })
        guard case .boolean(let answer)? = exported.enableWhen?.first?.answer else {
            Issue.record("Expected a boolean enableWhen answer")
            return
        }
        #expect(answer.value?.bool == false)
    }

    @Test
    func typedConditionsExportWithTheOptionSystem() throws {
        let fhir = try ModelsR4.Questionnaire(CheckIn.questionnaire)
        let followUp = try #require(fhir.item?.first?.item?.first { $0.linkId.value?.string == "follow-up" })
        // A branch keyed on a code with no system would never fire outside Grove.
        guard case .coding(let coding)? = followUp.enableWhen?.first?.answer else {
            Issue.record("Expected a coded enableWhen answer")
            return
        }
        #expect(coding.system?.value?.url == Frequency.system)
    }

    @Test
    func choiceInitialValuePreselectsAndExports() throws {
        let mood = ChoiceQuestion<Frequency>("mood", "Mood")
            .initialValue(.severalDays)
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/preselect")!,
            title: "Preselect"
        ) {
            Section("s1") { mood }
        }
        #expect(QuestionnaireResponses(questionnaire: questionnaire)[mood] == .severalDays)
        let fhir = try ModelsR4.Questionnaire(questionnaire)
        let item = try #require(fhir.item?.first?.item?.first)
        // que-11: the pre-selection rides the answerOption, not `initial`.
        #expect(item.initial == nil)
        #expect(item.answerOption?.compactMap { $0.initialSelected?.value?.bool } == [true])
        #expect(item.answerOption?[1].initialSelected?.value?.bool == true)
        let reimported = try GroveQuestionnaire.Questionnaire(fhir)
        #expect(QuestionnaireResponses(questionnaire: reimported)[mood] == .severalDays)
    }

    @Test
    func typedConditionsDriveEnablement() throws {
        let responses = QuestionnaireResponses(questionnaire: CheckIn.questionnaire)
        let followUpTask = try #require(CheckIn.questionnaire.sections.flatMap(\.tasks).first { $0.id == "follow-up" })
        #expect(!responses.shouldEnable(task: followUpTask))
        responses[CheckIn.mood] = .nearlyEveryDay
        #expect(responses.shouldEnable(task: followUpTask))
        responses[CheckIn.mood] = .notAtAll
        #expect(!responses.shouldEnable(task: followUpTask))
    }

    @Test
    func exportsToConformantFHIR() throws {
        let fhir = try ModelsR4.Questionnaire(CheckIn.questionnaire)
        #expect(fhir.url?.value?.url.absoluteString == "https://example.org/fhir/Questionnaire/check-in")
        #expect(fhir.version?.value?.string == "2.1.0")
        let group = try #require(fhir.item?.first)
        #expect(group.type.value == .group)
        let items = try #require(group.item)
        #expect(items.map { $0.linkId.value?.string } == ["intro", "interest", "mood", "total", "follow-up", "consented"])

        let interest = items[1]
        #expect(interest.type.value == .choice)
        #expect(interest.required?.value?.bool == true)
        #expect(interest.prefix?.value?.string == "1.")
        #expect(interest.answerOption?.count == 4)
        // Weights ride the option codings.
        guard case let .coding(lastCoding)? = interest.answerOption?.last?.value else {
            Issue.record("Expected coding options")
            return
        }
        #expect(!lastCoding.extensions(for: "http://hl7.org/fhir/StructureDefinition/itemWeight").isEmpty)

        let total = items[3]
        #expect(total.readOnly?.value?.bool == true)
        #expect(!total.extensions(for: "http://hl7.org/fhir/StructureDefinition/questionnaire-hidden").isEmpty)
        #expect(!total.extensions(for: "http://hl7.org/fhir/uv/sdc/StructureDefinition/sdc-questionnaire-calculatedExpression").isEmpty)

        let followUp = items[4]
        #expect(followUp.enableWhen?.count == 2)
        #expect(followUp.enableBehavior?.value == .any)

        let consent = items[5]
        guard case let .boolean(initial)? = consent.initial?.first?.value else {
            Issue.record("Expected a boolean initial")
            return
        }
        #expect(initial.value?.bool == true)
    }

    @Test
    func roundTripPreservesBehavior() throws {
        // Export the Swift-declared instrument to FHIR and read it back in.
        let fhir = try ModelsR4.Questionnaire(CheckIn.questionnaire)
        let reimported = try GroveQuestionnaire.Questionnaire(fhir)
        let responses = QuestionnaireResponses(questionnaire: reimported)

        // The typed handles keep working against the reimported questionnaire —
        // handles are erased to linkIds, so authoring and FHIR import converge.
        #expect(responses[CheckIn.consent] == true)

        // Selecting weighted options drives the calculated total via the engine.
        let scaleSystem = try #require(Frequency.system?.absoluteString)
        responses.responses["interest"] = .init(value: .choice(.init(selectedOptions: ["\(scaleSystem)|several-days"])))
        responses.responses["mood"] = .init(value: .choice(.init(selectedOptions: ["\(scaleSystem)|nearly-every-day"])))
        #expect(responses.responses["total"].value == .number(4))

        // The follow-up enablement carried over through enableWhen.
        let followUpTask = try #require(reimported.sections.flatMap(\.tasks).first { $0.id == "follow-up" })
        #expect(responses.shouldEnable(task: followUpTask))

        // And the collected answers export as a QuestionnaireResponse with the score.
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        #expect(fhirResponse.questionnaire?.value?.version == "2.1.0")
        let totalItem = fhirResponse.item?.first?.item?.first { $0.linkId.value?.string == "total" }
        #expect(totalItem?.answer?.first?.value == .decimal(FHIRPrimitive(FHIRDecimal(4))))
    }

    @Test
    func conditionalSectionsAndLoopsBuild() throws {
        let includeExtras = true
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: URL(string: "https://example.org/fhir/Questionnaire/builder-forms")!,
            title: "Builder Forms"
        ) {
            Section("always", title: "Always") {
                BooleanQuestion("q1", "First?")
                if includeExtras {
                    BooleanQuestion("q2", "Extra?")
                }
                for index in 0..<2 {
                    BooleanQuestion("loop-\(index)", "Loop \(index)?")
                }
            }
        }
        #expect(questionnaire.sections.flatMap(\.tasks).map(\.id) == ["q1", "q2", "loop-0", "loop-1"])
    }

    /// Groups are the DSL's way to structure a page without splitting it, and the only
    /// way a Swift-authored questionnaire can express the nesting FHIR allows.
    @Test
    func groupsExportAsNestedFHIRGroups() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/groups")),
            title: "Groups"
        ) {
            Section("s1", title: "Screening") {
                CheckIn.consent
                Group("recent-mood", title: "Over the last two weeks") {
                    CheckIn.interest
                    CheckIn.mood
                }
                .enabledWhen(CheckIn.consent.isTrue)
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)

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
        let group = try #require(find("recent-mood", fhir.item ?? []))
        #expect(group.type.value == .group)
        #expect(group.text?.value?.string == "Over the last two weeks")
        #expect(group.enableWhen?.first?.question.value?.string == "consented")
        #expect(group.item?.compactMap { $0.linkId.value?.string } == ["interest", "mood"])
    }

    @Test
    func groupsNest() throws {
        let questionnaire = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/nested")),
            title: "Nested"
        ) {
            Section("s1") {
                Group("outer", title: "Outer") {
                    Group("inner", title: "Inner") {
                        CheckIn.mood
                    }
                }
            }
        }
        let fhir = try ModelsR4.Questionnaire(questionnaire)

        // The section is itself a group, so the nesting is s1 > outer > inner.
        let section = try #require(fhir.item?.first { $0.linkId.value?.string == "s1" })
        let outer = try #require(section.item?.first { $0.linkId.value?.string == "outer" })
        let inner = try #require(outer.item?.first { $0.linkId.value?.string == "inner" })
        #expect(inner.text?.value?.string == "Inner")
        #expect(inner.item?.compactMap { $0.linkId.value?.string } == ["mood"])
    }

    /// Scoring must work for a questionnaire declared in Swift, not only for one imported
    /// from FHIR. The engine is attached by the FHIR import, so a natively declared
    /// instrument computed nothing at all until `withExpressionEngine()` existed — and
    /// every scoring test here went through a round trip, which hid it.
    @Test
    func aNativelyDeclaredQuestionnaireEvaluatesItsScore() throws {
        let questionnaire = try CheckIn.questionnaire.withExpressionEngine()
        let responses = QuestionnaireResponses(questionnaire: questionnaire)

        responses[CheckIn.interest] = .severalDays
        responses[CheckIn.mood] = .nearlyEveryDay

        #expect(responses.responses["total"].value == .number(4), "1 + 3 from the option weights")
    }

    /// A computed question cannot be answered by the participant, so requiring one would
    /// leave its section permanently incomplete.
    @Test
    func calculatedQuestionsAreNotRequired() throws {
        let total = try #require(CheckIn.questionnaire.sections.flatMap(\.tasks).first { $0.id == "total" })
        #expect(total.isOptional)
    }

    /// `.followUp { … }` is sugar over `ChoiceConfig.followUpTasks`, so it has to compile
    /// to the very value the model initialisers build — anything else moves the exported FHIR.
    @Test
    func followUpsBuildTheSameTaskAsTheModelInitialisers() throws {
        let activitySystem = try #require(Activity.system)
        let cadenceSystem = try #require(Cadence.system)
        func option(_ system: URL, _ code: String, _ title: String) -> GroveQuestionnaire.Questionnaire.Task.Kind.ChoiceConfig.Option {
            .init(id: "\(system.absoluteString)|\(code)", title: title, fhirCoding: .init(system: system, code: code))
        }
        let handWritten = GroveQuestionnaire.Questionnaire.Task(
            id: "activities",
            title: "Which activities did you do?",
            kind: .choice(.init(
                options: [option(activitySystem, "running", "Running"), option(activitySystem, "cycling", "Cycling")],
                allowsMultipleSelection: true,
                followUpTasks: [
                    .init(id: "cadence", title: "How often?", kind: .choice(.init(
                        options: [option(cadenceSystem, "daily", "Daily"), option(cadenceSystem, "weekly", "Once per week")],
                        allowsMultipleSelection: false
                    ))),
                    .init(id: "minutes", title: "How many minutes each time?", kind: .numeric(.init(
                        inputMode: .numberPad(.integer),
                        valueKind: .integer
                    )))
                ]
            ))
        )
        #expect(ActivityLog.questionnaire.sections.flatMap(\.tasks) == [handWritten])
    }

    /// Follow-ups export as items nested beneath the question — FHIR's own "asked in the
    /// context of each answer" — rather than as siblings gated by `enableWhen`.
    @Test
    func followUpsExportAsItemsNestedBeneathTheQuestion() throws {
        let fhir = try ModelsR4.Questionnaire(ActivityLog.questionnaire)
        let activities = try #require(fhir.item?.first?.item?.first { $0.linkId.value?.string == "activities" })
        #expect(activities.type.value == .choice)
        #expect(activities.repeats?.value?.bool == true)
        #expect(activities.item?.map { $0.linkId.value?.string } == ["cadence", "minutes"])
        // A follow-up is not a gated sibling: nothing was lifted next to the question.
        #expect(fhir.item?.first?.item?.map { $0.linkId.value?.string } == ["activities"])
    }

    /// And their answers ride the answer they were given for, one nesting per selected option.
    @Test
    func followUpAnswersExportUnderTheirOption() throws {
        let system = try #require(Activity.system?.absoluteString)
        let responses = QuestionnaireResponses(questionnaire: ActivityLog.questionnaire)
        responses[ActivityLog.activities] = [.running]
        responses.responses["activities"].nestedResponses = [
            .choiceOption("\(system)|running"): .init(["minutes": .init(value: .number(30))])
        ]
        let fhirResponse = try ModelsR4.QuestionnaireResponse(responses)
        let activities = try #require(fhirResponse.item?.first?.item?.first { $0.linkId.value?.string == "activities" })
        let answer = try #require(activities.answer?.first)
        guard case .coding(let coding)? = answer.value else {
            Issue.record("Expected a coded answer, got \(String(describing: answer.value))")
            return
        }
        #expect(coding.code?.value?.string == "running")
        #expect(answer.item?.map { $0.linkId.value?.string } == ["minutes"])
        #expect(answer.item?.first?.answer?.first?.value == .integer(FHIRPrimitive(FHIRInteger(30))))
    }

    /// Follow-ups share the questionnaire's identifier space, so the declaration check has
    /// to descend into them; a questionnaire that dropped them must not pass.
    @Test
    func followUpLinkIDsCountAsPartOfTheInstrument() throws {
        #expect(ActivityLog.declaredLinkIDs == ["activities", "cadence"])
        #expect(ActivityLog.questionnaire.allLinkIDs.isSuperset(of: ["activities", "cadence", "minutes"]))
        #expect(throws: Never.self) {
            try ActivityLog.questionnaire.checkDeclaration(of: ActivityLog.self)
        }

        let withoutFollowUps = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/activity-log")),
            title: "Activity Log"
        ) {
            Section("log", title: "Your Week") {
                ActivityLog.activities
            }
        }
        #expect(throws: GroveQuestionnaire.Questionnaire.DeclarationMismatch.self) {
            try withoutFollowUps.checkDeclaration(of: ActivityLog.self)
        }
    }
}

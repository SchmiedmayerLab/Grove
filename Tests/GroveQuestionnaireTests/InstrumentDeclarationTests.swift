//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveQuestionnaire
import Testing


@Instrument
@available(iOS 18, macOS 15, watchOS 11, *)
private enum Screener {
    static let consent = BooleanQuestion("consented", "Happy to continue?")
    static let symptoms = Group("symptoms", title: "Symptoms") {
        cough
    }
    static let cough = BooleanQuestion("cough", "Any cough?")
    static let followUp = TextQuestion("cough-detail", "Tell us more")
        .enabledWhen(cough.isTrue)
        .optional()

    static let questionnaire = GroveQuestionnaire.Questionnaire(
        url: URL(string: "https://example.org/fhir/Questionnaire/screener")!,
        title: "Screener"
    ) {
        Section("intake", title: "Intake") {
            consent
            symptoms
            followUp
        }
    }
}


/// What `@Instrument` and the model's integrity check buy at the boundary where the
/// compiler stops: a named declaration, and a questionnaire that can be checked against it.
@Suite
struct InstrumentDeclarationTests {
    /// The macro publishes the instrument's linkIds under their Swift names, in declaration
    /// order, so a linkId is written once and read everywhere else through the compiler.
    @Test
    func theMacroPublishesDeclaredLinkIDs() {
        #expect(Screener.declaredLinkIDs == ["consented", "symptoms", "cough", "cough-detail"])
        #expect(Screener.LinkID.followUp.rawValue == "cough-detail")
        #expect(Screener.LinkID.allCases.map(\.rawValue) == Screener.declaredLinkIDs)
    }

    @Test
    func aQuestionnaireMatchesItsOwnDeclaration() throws {
        try Screener.questionnaire.checkDeclaration(of: Screener.self)
    }

    /// The case the check exists for: a questionnaire that came from somewhere else and no
    /// longer carries an item the app's typed handles read.
    @Test
    func aDriftedQuestionnaireReportsWhatIsMissing() throws {
        let drifted = GroveQuestionnaire.Questionnaire(
            url: try #require(URL(string: "https://example.org/fhir/Questionnaire/screener")),
            title: "Screener"
        ) {
            Section("intake", title: "Intake") {
                Screener.consent
                Screener.cough
                BooleanQuestion("added-by-the-server", "New question?")
            }
        }
        let mismatch = #expect(throws: GroveQuestionnaire.Questionnaire.DeclarationMismatch.self) {
            try drifted.checkDeclaration(of: Screener.self)
        }
        #expect(mismatch?.missing == ["cough-detail", "symptoms"])
        #expect(mismatch?.unexpected.contains("added-by-the-server") == true)
    }

    /// Hostile content used to trip a `precondition` and take the app with it.
    @Test
    func collidingIdentifiersAreReportedRatherThanTrapped() throws {
        let metadata = GroveQuestionnaire.Questionnaire.Metadata(
            id: "collision",
            url: nil,
            title: "Collision",
            explainer: ""
        )
        let task = GroveQuestionnaire.Questionnaire.Task(id: "q1", title: "First?", kind: .boolean)
        #expect(throws: GroveQuestionnaire.Questionnaire.IntegrityError.duplicateTask(id: "q1")) {
            _ = try GroveQuestionnaire.Questionnaire.validated(
                metadata: metadata,
                sections: [.init(id: "a", tasks: [task]), .init(id: "b", tasks: [task])]
            )
        }
        #expect(throws: GroveQuestionnaire.Questionnaire.IntegrityError.duplicateSection(id: "a")) {
            _ = try GroveQuestionnaire.Questionnaire.validated(
                metadata: metadata,
                sections: [.init(id: "a", tasks: [task]), .init(id: "a", tasks: [])]
            )
        }
    }

    /// The builders take components and nothing else, and every block has to produce one.
    /// None of these compile:
    ///
    /// ```swift
    /// Section("empty") { }                              // no buildBlock() for an empty block
    /// Section("s") { cough.isTrue }                     // a condition belongs on an item
    /// Section("s") { "Some text" }                      // text needs an Instruction
    /// Section("s") { Section("nested") { cough } }      // sections do not nest
    /// Questionnaire(url: …, title: …) { cough }         // a questionnaire is built from Sections
    /// ```
    @Test
    func buildersTakeComponentsOnly() {
        let tasks = Screener.questionnaire.sections.flatMap(\.tasks)
        #expect(tasks.map(\.id) == ["consented", "cough", "cough-detail"])
        #expect(tasks.first { $0.id == "cough" }?.groupPath.map(\.id) == ["symptoms"])
    }
}

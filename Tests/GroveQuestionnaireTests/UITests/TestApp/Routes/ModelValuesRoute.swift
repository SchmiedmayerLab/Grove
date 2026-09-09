//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import GroveQuestionnaireUI
import GroveQuestionnaireCatalog
import SwiftUI


/// Questionnaires assembled from the model's own initialisers, which is also where the features
/// the DSL has no spelling for live.
struct ModelValuesRoute: View {
    var body: some View {
        ExampleCatalog(route: .modelValues, groups: [
            ExampleGroup("Instruments", [
                // The nine-item depression screener, and the one example that shows question progress.
                Example(.phq9, questionProgressConfig: .enable),
                // The seven-item anxiety screener, built the same way.
                Example(.gad7)
            ]),
            ExampleGroup("Conditions", [
                // A question that appears once the one above it is answered.
                Example(.simpleCondition),
                // The same condition, reaching back to an answer given on an earlier page.
                Example(.crossSectionCondition),
                // One section gates on a later question and never fires; the next gates correctly.
                Example(.conditionLookupRules),
                // A follow-up gated on another follow-up of the same question.
                Example(.nestedQuestionCondition),
                // When every follow-up is disabled, the follow-up page is skipped outright.
                Example(.followUpTasksSkippedIfNoneEnabled)
            ]),
            ExampleGroup("Page Layout", [
                // One page per shape a page takes when it names itself, short names included.
                Example(.pageTitles)
            ]),
            ExampleGroup("Question Kinds", [
                // Every kind the model offers, one question per page.
                Example(.inputKinds),
                // Integer and decimal entry through the number pad.
                Example(.simpleNumberEntry),
                // Coded options plus a free-text answer (FHIR open-choice).
                Example(.openChoice),
                // Display items render Markdown, lists and paragraphs included.
                Example(.markdownInstructions),
                // A photo answer, exported as a FHIR Attachment.
                Example(.fileAttachment),
                // Marking named regions on a body map.
                Example(.annotateImage),
                // The same task with an image far taller than the screen.
                Example(.annotateTallImage)
            ]),
            ExampleGroup("Custom Question Kinds", [
                // An app-defined question whose validation blocks the section until it is accepted.
                Example(.consentAcknowledgement),
                // An app-defined question that encodes itself as a UCUM Quantity in seconds.
                Example(.stopwatch)
            ])
        ])
    }
}

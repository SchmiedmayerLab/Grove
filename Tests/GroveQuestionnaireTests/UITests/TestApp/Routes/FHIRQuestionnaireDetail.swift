//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import GroveQuestionnaireFHIR
import GroveQuestionnaireLegacy
import ModelsR4
import SwiftUI


/// A FHIR resource and the model it decodes to, with the renderer one tap away.
struct FHIRQuestionnaireDetail: View {
    let example: FHIRExample

    @Environment(ResponsesStore.self) private var responsesStore

    @State private var converted: Result<GroveQuestionnaire.Questionnaire, any Error>?
    @State private var running: Example?
    @State private var runningLegacy = false

    var body: some View {
        List {
            Section("Source") {
                LabeledContent("Status", value: example.fhir.status.value?.rawValue ?? "—")
                    .accessibilityIdentifier("Source:Status")
                NavigationLink("FHIR JSON") {
                    FHIRSourceView(title: example.title, json: example.fhir.prettyPrintedJSON)
                }
                .accessibilityIdentifier("Source:FHIR JSON")
            }

            switch converted {
            case .success(let questionnaire):
                modelSection(for: questionnaire)
                actionsSection(for: questionnaire)
            case .failure(let error):
                Section("Model") {
                    Text(String(describing: error))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("ConversionError")
                }
            case nil:
                Section("Model") {
                    ProgressView()
                }
            }
        }
        .navigationTitle(example.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            converted = Result { try GroveQuestionnaire.Questionnaire(example.fhir) }
        }
        .runsQuestionnaires($running)
        .sheet(isPresented: $runningLegacy) {
            QuestionnaireView(questionnaire: example.fhir, completionStepMessage: "Completed") { result in
                if case .completed(let response) = result {
                    responsesStore.record(response, from: "\(example.title) (ResearchKit)")
                }
                runningLegacy = false
            }
        }
    }

    private func modelSection(for questionnaire: GroveQuestionnaire.Questionnaire) -> some View {
        Section("Model") {
            LabeledContent("Pages", value: questionnaire.sections.count, format: .number)
                .accessibilityIdentifier("Model:Pages")
            LabeledContent("Questions", value: questionnaire.sections.map(\.tasks.count).reduce(0, +), format: .number)
                .accessibilityIdentifier("Model:Questions")
            LabeledContent("Entry Mode", value: questionnaire.metadata.entryMode.rawValue)
                .accessibilityIdentifier("Model:Entry Mode")
            ForEach(questionnaire.metadata.administrationWarnings, id: \.self) { warning in
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func actionsSection(for questionnaire: GroveQuestionnaire.Questionnaire) -> some View {
        Section {
            Button("Start Questionnaire") {
                running = Example(questionnaire, title: example.title)
            }
            .accessibilityIdentifier("StartQuestionnaire")
            // The ResearchKit renderer draws the same resource, for comparison while apps migrate.
            Button("Open in the Legacy Renderer") {
                runningLegacy = true
            }
            .accessibilityIdentifier("StartLegacyQuestionnaire")
        }
    }
}

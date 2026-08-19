//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRQuestionnaires
import Foundation
import GroveQuestionnaireFHIR
import GroveViews
import struct ModelsR4.Questionnaire
import SwiftUI
import UniformTypeIdentifiers


/// Questionnaires that arrive as FHIR R4 JSON — the bundled examples, or one picked off disk.
///
/// Every row leads to the resource behind it, so the JSON and the rendered questionnaire can be
/// read side by side.
struct FHIRRoute: View {
    private static let researchInstruments: [FHIRExample] = [
        // Nine coded items with an enableWhen tail.
        .init(.phq9),
        // Seven items sharing one contained answer ValueSet.
        .init(.gad7),
        // Symptom score with a quality-of-life item on its own scale.
        .init(.ipss),
        // Three scored scales, each option carrying its weight.
        .init(.gcs)
    ]

    private static let sdcExamples: [FHIRExample] = [
        // enableWhen driving what gets asked next.
        .init(.skipLogicExample),
        // Several conditions on one item, any and all.
        .init(.multipleEnableWhen),
        // regex, minLength and maxLength on free text.
        .init(.textValidationExample),
        // Answer options resolved from a contained ValueSet.
        .init(.containedValueSetExample),
        // Integer, decimal and quantity items with unit codes.
        .init(.numberExample),
        // date, time and dateTime items.
        .init(.dateTimeExample),
        // Nested groups rendered as one form.
        .init(.formExample),
        // An attachment item that asks for a photo.
        .init(.imageCaptureExample),
        // The slider itemControl with a step size.
        .init(.sliderExample)
    ]

    @State private var imported: FHIRExample?
    @State private var showFileImporter = false
    @State private var viewState: ViewState = .idle

    var body: some View {
        List {
            Section {
                Button("Import from File…") {
                    showFileImporter = true
                }
                .accessibilityIdentifier("ImportQuestionnaire")
                if let imported {
                    row(for: imported)
                }
            }

            Section("Research Instruments") {
                ForEach(Self.researchInstruments) { example in
                    row(for: example)
                }
            }

            Section("SDC Examples") {
                ForEach(Self.sdcExamples) { example in
                    row(for: example)
                }
            }
        }
        .navigationTitle(AuthoringRoute.fhir.title)
        .viewStateAlert(state: $viewState)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            do {
                imported = try FHIRExample(importedFrom: result.get())
            } catch {
                viewState = .error(AnyLocalizedError(error: error))
            }
        }
    }

    private func row(for example: FHIRExample) -> some View {
        NavigationLink(example.title) {
            FHIRQuestionnaireDetail(example: example)
        }
        .accessibilityIdentifier("Example:\(example.title)")
    }
}


/// A FHIR resource the catalog offers, kept in its source form until the detail page converts it.
struct FHIRExample: Identifiable, Sendable {
    let title: String
    let fhir: ModelsR4.Questionnaire

    var id: String {
        title
    }

    init(_ fhir: ModelsR4.Questionnaire) {
        self.title = fhir.title?.value?.string ?? fhir.id?.value?.string ?? "Untitled"
        self.fhir = fhir
    }

    init(importedFrom url: URL) throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        self.init(try JSONDecoder().decode(ModelsR4.Questionnaire.self, from: try Data(contentsOf: url)))
    }
}

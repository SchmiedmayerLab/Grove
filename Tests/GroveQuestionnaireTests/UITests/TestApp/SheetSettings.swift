//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveQuestionnaire
import Observation
import SwiftUI


/// What the sheet is opened with, on top of what each example asks for.
///
/// Every setting starts out deferring to the example, so the catalog and the UI tests see the sheet as
/// the examples define it until someone flips a setting on or off for every example at once.
@Observable
@MainActor
final class SheetSettings {
    enum Override: String, CaseIterable, Identifiable {
        case example = "Example"
        case on = "On"
        case off = "Off"

        var id: Self {
            self
        }

        func resolve(_ value: Bool) -> Bool {
            switch self {
            case .example:
                value
            case .on:
                true
            case .off:
                false
            }
        }
    }

    var progressBar: Override = .example
    var questionNumbers: Override = .example
    var selectAllHint: Override = .example
    var completionPage: Override = .example
    var doneInsteadOfSubmit: Override = .example

    func progress(for example: Example) -> QuestionnaireProgress {
        var progress: QuestionnaireProgress = []
        if progressBar.resolve(example.progress.contains(.bar)) {
            progress.insert(.bar)
        }
        if questionNumbers.resolve(example.progress.contains(.questionNumbers)) {
            progress.insert(.questionNumbers)
        }
        return progress
    }

    func hints(for example: Example) -> QuestionnaireHints {
        selectAllHint.resolve(example.hints.contains(.selectAllThatApply)) ? [.selectAllThatApply] : []
    }

    func completionStepConfig(for example: Example) -> CompletionStepConfig {
        completionPage.resolve(example.completionStepConfig == .enable) ? .enable : .disable
    }

    func completionAction(for example: Example) -> CompletionAction {
        doneInsteadOfSubmit.resolve(example.completionAction == .done) ? .done : .submit
    }
}


/// A sheet to flip the settings for every example at once.
struct SheetSettingsView: View {
    @Environment(SheetSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Progress") {
                    picker("Progress Bar", $settings.progressBar)
                    picker("Question Numbers", $settings.questionNumbers)
                }
                Section("Questions") {
                    picker("Select All That Apply", $settings.selectAllHint)
                }
                Section("Completion") {
                    picker("Completion Page", $settings.completionPage)
                    picker("Done Instead of Submit", $settings.doneInsteadOfSubmit)
                }
            }
            .navigationTitle("Sheet Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") {
                    dismiss()
                }
                .accessibilityIdentifier("Settings:Done")
            }
        }
    }

    private func picker(_ title: String, _ selection: Binding<SheetSettings.Override>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SheetSettings.Override.allCases) { override in
                Text(override.rawValue)
            }
        }
        .accessibilityIdentifier("Setting:\(title)")
    }
}

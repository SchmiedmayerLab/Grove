//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveQuestionnaire
public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension AnnotateImageQuestionKind: QuestionKindDefinitionWithViewSupport {
    public static func makeView(
        for task: Questionnaire.Task,
        using config: AnnotateImageConfig,
        response: Binding<QuestionnaireResponses.Response>
    ) -> some View {
        #if canImport(UIKit)
        AnnotateImageView(
            task: task,
            config: config,
            response: response.value.annotatedImageValue.withDefault(.init())
        )
        #else
        // Image annotation is implemented on top of UIKit and PencilKit. The question kind itself is
        // platform-neutral — a questionnaire using it still parses, converts, and stores here — but without
        // UIKit there is no editor, so the task shows only its title and subtitle.
        //
        // ISSUE: the task nonetheless takes part in completeness checking (`validate` returns `.ok`, but
        // `QuestionnaireResponses.isMissingResponse(for:)` keeps returning true, since no response can ever be produced).
        // A *required* annotate-image task therefore is an unsatisfiable blocker on these platforms: the section, and
        // the questionnaire, can never be completed.
        EmptyView()
        #endif
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Color {
    /// Renders a questionnaire-declared region colour.
    package init(_ color: AnnotationColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.opacity)
    }
}

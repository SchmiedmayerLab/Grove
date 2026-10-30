//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveQuestionnaire
public import SwiftUI


/// A question kind that can be presented on screen.
///
/// ## Topics
///
/// ### Static Methods
/// - ``makeView(for:using:response:)``
///
/// ### Associated Types
/// - ``View``
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol QuestionKindDefinitionWithViewSupport: QuestionKindDefinition {
    associatedtype View: SwiftUI.View

    /// Constructs a SwiftUI view usable for responding to a question of this kind.
    ///
    /// - Note: The resulting view will be placed into a `Section` within a `Form`, i.e. each element in the view will become a row in the `Form`.
    @MainActor
    @ViewBuilder
    static func makeView(
        for task: Questionnaire.Task,
        using config: Config,
        response: Binding<QuestionnaireResponses.Response>
    ) -> View
}

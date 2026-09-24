//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import GroveQuestionnaire
import GroveQuestionnaireFHIR
@testable import GroveQuestionnaireUI
import ModelsR4
import SwiftUI


/// A custom question kind that also says how it travels to FHIR.
///
/// Conforming to ``QuestionKindDefinitionWithFHIREncodingSupport`` is what lets an app-defined
/// question end up in the `QuestionnaireResponse` as a proper coded value — here a UCUM
/// `Quantity` in seconds rather than a bare number.
struct StopwatchQuestionKind: QuestionKindDefinitionWithViewSupport {
    typealias Config = EmptyQuestionKindConfig

    static func validate(
        response: QuestionnaireResponses.Response,
        for config: Config
    ) -> QuestionnaireResponses.ResponseValidationResult {
        .ok
    }

    static func makeView(
        for task: GroveQuestionnaire.Questionnaire.Task,
        using config: Config,
        response: Binding<QuestionnaireResponses.Response>
    ) -> some View {
        StopwatchView(elapsed: response.value.numberValue.withDefault(0))
    }
}


extension StopwatchQuestionKind: QuestionKindDefinitionWithFHIREncodingSupport {
    static func toFHIR(
        _ response: QuestionnaireResponses.Response,
        for task: GroveQuestionnaire.Questionnaire.Task
    ) throws -> [QuestionnaireResponseItemAnswer] {
        guard let duration = response.value.numberValue else {
            return []
        }
        return [
            QuestionnaireResponseItemAnswer(
                value: .quantity(Quantity(
                    code: "s",
                    system: "http://unitsofmeasure.org",
                    unit: "seconds",
                    value: duration.asFHIRDecimalPrimitive()
                ))
            )
        ]
    }
}


extension GroveQuestionnaire.Questionnaire.Task.Kind {
    static var stopwatch: Self {
        .custom(StopwatchQuestionKind.self, config: .init())
    }
}


private struct StopwatchView: View {
    @Binding var elapsed: TimeInterval
    @State private var startDate: Date?

    var body: some View {
        HStack {
            Group {
                if let startDate {
                    Text(startDate - elapsed, style: .timer)
                } else {
                    Text(Swift.Duration.seconds(elapsed), format: .time(pattern: .minuteSecond))
                }
            }
            .font(.title.monospacedDigit())
            .accessibilityIdentifier("StopwatchElapsed")
            Spacer()
            Button(startDate == nil ? "Start" : "Stop") {
                if let startDate {
                    elapsed += Date().timeIntervalSince(startDate)
                    self.startDate = nil
                } else {
                    startDate = Date()
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("StopwatchToggle")
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
extension TaskView {
    struct NumericInputRow: View {
        let label: String
        let config: Questionnaire.Task.Kind.NumericTaskConfig
        @Binding var value: QuestionnaireResponses.Response.Value

        var body: some View {
            HStack {
                inputControl
                if config.unitOptions.count > 1 {
                    unitPicker
                } else if let unit = singleUnitDisplay {
                    // Without it the participant is asked for a number and never told of what.
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }

        /// The one unit the answer is measured in, when the question does not offer a choice.
        private var singleUnitDisplay: String? {
            guard config.unitOptions.count <= 1 else {
                return nil
            }
            let display = config.unitOptions.first?.display ?? config.unit
            return display.isEmpty ? nil : display
        }

        @ViewBuilder private var inputControl: some View {
            switch config.inputMode {
            case .numberPad(let numberKind):
                numberPad(numberKind)
            case .slider(let stepValue):
                if let minimum = config.minimum, let maximum = config.maximum {
                    slider(bounds: minimum...maximum, stepValue: stepValue)
                } else {
                    // if we don't have both limits, we fall back to the number-pad-based input
                    numberPad(.decimal)
                }
            }
        }

        /// The number, written back as a plain number or — when the participant can
        /// choose among units — as a quantity carrying the selected unit code.
        private var response: Binding<Double?> {
            Binding {
                value.numberValue
            } set: { newValue in
                guard let newValue else {
                    value = .none
                    return
                }
                if config.unitOptions.count > 1 {
                    value = .quantity(newValue, unitCode: selectedUnitCode)
                } else {
                    value = .number(newValue)
                }
            }
        }

        private var selectedUnitCode: String {
            value.quantityValue?.unitCode ?? config.unitCode ?? config.unitOptions.first?.code ?? config.unit
        }

        /// The unit chooser for `questionnaire-unitOption` items.
        private var unitPicker: some View {
            Picker(selection: Binding {
                selectedUnitCode
            } set: { newUnit in
                if let number = value.numberValue {
                    value = .quantity(number, unitCode: newUnit)
                }
            }) {
                ForEach(config.unitOptions, id: \.code) { option in
                    Text(option.display)
                        .tag(option.code)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .accessibilityLabel(Text("Unit", bundle: .module))
        }
        
        /// What the field shows while it is empty: the range asked for, or failing that the
        /// kind of thing wanted. A `0` placeholder used to read as an answer already given.
        private var prompt: Text {
            if let minimum = config.minimum, let maximum = config.maximum {
                Text(verbatim: "\(minimum.formatted(.number)) – \(maximum.formatted(.number))")
            } else {
                Text("Enter a number", bundle: .module)
            }
        }

        /// The question, and the unit its answer is measured in, as one spoken label.
        private var spokenLabel: String {
            guard let unit = singleUnitDisplay else {
                return label
            }
            return "\(label), \(unit)"
        }

        @ViewBuilder
        private func numberPad(_ numberKind: Questionnaire.Task.Kind.NumericTaskConfig.NumberKind) -> some View {
            NumberTextField(
                value: response,
                prompt: prompt,
                allowsDecimalEntry: { () -> Bool in
                    switch numberKind {
                    case .integer:
                        false
                    case .decimal:
                        true
                    }
                }()
            )
            .accessibilityLabel(spokenLabel)
            .enableDismissalViaKeyboardAccessory()
        }

        @ViewBuilder
        private func slider(bounds: ClosedRange<Double>, stepValue: Double) -> some View {
            let binding = Binding<Double> {
                response.wrappedValue ?? (bounds.contains(0) ? 0 : bounds.lowerBound)
            } set: { newValue in
                response.wrappedValue = newValue
            }
            VStack {
                // An unanswered slider reads out as whatever it is resting on, so a number here
                // would claim an answer nobody gave.
                if response.wrappedValue == nil {
                    Text(verbatim: "—")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                } else {
                    Text(binding.wrappedValue, format: .number)
                        .font(.title2)
                        .bold()
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
                Slider(value: binding, in: bounds, step: stepValue) {
                    EmptyView() // doesn't seem to get displayed anyway?
                } minimumValueLabel: {
                    Text(bounds.lowerBound, format: .number)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(bounds.upperBound, format: .number)
                        .foregroundStyle(.secondary)
                } onEditingChanged: { isEditing in
                    // Touching the slider answers it, even when the thumb does not move: the
                    // resting value is otherwise unreachable, because it is already selected.
                    if !isEditing {
                        response.wrappedValue = binding.wrappedValue
                    }
                }
                .accessibilityLabel(spokenLabel)
            }
            .padding(.vertical, 8)
        }
    }
}


private struct NumberTextField<Value: BinaryFloatingPoint>: View {
    // Note: using a NumberFormatter() instead of the new `FloatingPointFormatStyle<Double>.number` API,
    // because of https://github.com/swiftlang/swift-foundation/issues/135
    @State private var formatter = NumberFormatter()

    private let prompt: Text
    private let allowsDecimalEntry: Bool
    @Binding private var value: Value?

    var body: some View {
        TextField("", value: $value, formatter: formatter, prompt: prompt)
            #if os(iOS)
            .keyboardType(allowsDecimalEntry ? .decimalPad : .numberPad)
            #endif
    }

    init(value: Binding<Value?>, prompt: Text, allowsDecimalEntry: Bool) {
        self._value = value
        self.prompt = prompt
        self.allowsDecimalEntry = allowsDecimalEntry
    }
}

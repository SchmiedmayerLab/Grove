//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
struct DatePickerRow: View {
    @Environment(\.calendar) private var cal
    let label: String
    let config: Questionnaire.Task.Kind.DateTimeConfig
    @Binding var response: DateComponents?
    @State private var isPicking = false

    var body: some View {
        let binding = Binding<Date> {
            if let response {
                // should ideally never fail
                cal.date(from: response) ?? .now
            } else {
                .now
            }
        } set: { newValue in
            response = cal.dateComponents(config.style.components, from: newValue)
        }
        // A pill of our own rather than the compact picker, which reads out today while the page still counts
        // the question as unanswered. Opening it is the first answer: today, or now, until changed.
        LabeledContent {
            Button {
                if response == nil {
                    response = cal.dateComponents(config.style.components, from: .now)
                }
                isPicking = true
            } label: {
                AnswerPill(text: pillText, isPlaceholder: response == nil)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPicking, arrowEdge: .top) {
                picker(binding)
                    .labelsHidden()
                    .padding()
                    // The calendar lays itself out to the width it is given; a popover gives it none.
                    .frame(width: config.style == .timeOnly ? 240 : 340)
                    .presentationCompactAdaptation(.popover)
            }
        } label: {
            Text(fieldLabel)
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(pillText)
    }

    /// The placeholder until there is an answer, then the answer.
    private var pillText: Text {
        if let response, let date = cal.date(from: response) {
            Text(date, format: format)
        } else {
            Text(placeholder)
        }
    }

    /// What the row says before there is an answer.
    private var placeholder: LocalizedStringResource {
        switch config.style {
        case .dateOnly:
            LocalizedStringResource("Choose a date", bundle: .module)
        case .timeOnly:
            LocalizedStringResource("Choose a time", bundle: .module)
        case .dateAndTime:
            LocalizedStringResource("Choose a date and time", bundle: .module)
        }
    }

    /// What the row calls the control. Kept to a word or two: the question above already asks
    /// for the date, and a sentence here pushes the picker onto a line of its own.
    private var fieldLabel: LocalizedStringResource {
        switch config.style {
        case .dateOnly:
            LocalizedStringResource("Date", bundle: .module)
        case .timeOnly:
            LocalizedStringResource("Time", bundle: .module)
        case .dateAndTime:
            LocalizedStringResource("Date & Time", bundle: .module)
        }
    }
    
    private var format: Date.FormatStyle {
        switch config.style {
        case .dateOnly: .dateTime.year().month().day()
        case .timeOnly: .dateTime.hour().minute()
        case .dateAndTime: .dateTime.year().month().day().hour().minute()
        }
    }

    private var components: DatePickerComponents {
        switch config.style {
        case .dateOnly:
            .date
        case .timeOnly:
            .hourAndMinute
        case .dateAndTime:
            [.date, .hourAndMinute]
        }
    }

    /// A calendar for dates, a wheel for a time on its own, since a calendar has nothing to show for one.
    @ViewBuilder
    private func picker(_ binding: Binding<Date>) -> some View {
        let picker = DatePicker(fieldLabel, selection: binding, displayedComponents: components)
        if config.style == .timeOnly {
            #if os(macOS)
            picker.datePickerStyle(.stepperField)
            #else
            picker.datePickerStyle(.wheel)
            #endif
        } else {
            picker.datePickerStyle(.graphical)
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Questionnaire.Task.Kind.DateTimeConfig.Style {
    var components: Set<Calendar.Component> {
        switch self {
        case .dateOnly:
            [.year, .month, .day]
        case .timeOnly:
            [.hour, .minute, .second]
        case .dateAndTime:
            [.year, .month, .day, .hour, .minute, .second]
        }
    }
}

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
        // A picker always reads out something, so an untouched one shows today and looks answered
        // while the page still counts it as missing. Until there is an answer the row offers to
        // take one instead, the way a form asks for a date it does not have.
        if response == nil {
            Button {
                response = cal.dateComponents(config.style.components, from: .now)
            } label: {
                LabeledContent {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                } label: {
                    Text(fieldLabel)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityLabel(label)
            .accessibilityValue(Text(placeholder))
        } else {
            DatePicker(fieldLabel, selection: binding, displayedComponents: components)
                .datePickerStyle(.compact)
                .frame(minHeight: 44)
                .accessibilityLabel(label)
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

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import SwiftUI


/// A row in a single/multiple choice picker
struct ChoiceRow<AccessoryIfSelected: View>: View {
    /// The row's identifier; used for the view's UI testing accessibility identifier
    private var id: String
    private let title: String
    private let subtitle: String
    private let isSelected: Bool
    private let isSeparated: Bool
    private let action: @MainActor () -> Void
    private let accessoryIfSelected: @MainActor () -> AccessoryIfSelected

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(markdown: title)
                    if !subtitle.isEmpty {
                        Text(markdown: subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    accessoryIfSelected()
                }
                selectionMark
            }
            // The option is a row within its question's card rather than a row of the list, so it
            // carries the height and the tappable width the list would have given it. The padding
            // is what keeps the text off the rules once an accessibility size outgrows 44pt.
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel({ () -> Text in
                if isSelected {
                    Text("Option: \(title), Selected", bundle: .module)
                } else {
                    Text("Option: \(title), Not Selected", bundle: .module)
                }
            }())
            .accessibilityIdentifier("Choice:\(id)")
        }
        // Every option of a question shares one row of the list. Under the automatic style that
        // row is a single button: the options come out tinted like links, and a tap on one of
        // them fires all of them, so choosing Yes immediately toggles No back off again.
        .buttonStyle(.plain)
        // Each row draws the rule above itself. Placed between the rows instead, as its own view,
        // it is dropped when the card's contents are flattened into the list — which is how
        // whole option lists came to be ruled inconsistently, and yes/no questions not at all.
        .overlay(alignment: .top) {
            if isSeparated {
                Divider()
                    .allowsHitTesting(false)
            }
        }
    }

    /// Shape as well as colour, so the selection survives a colour-blind reading.
    @ViewBuilder private var selectionMark: some View {
        let mark = Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
        if #available(iOS 17, macOS 14, watchOS 10, *) {
            // The mark is the whole confirmation an answer gets, so it is worth seeing arrive.
            mark.contentTransition(.symbolEffect(.replace))
        } else {
            mark
        }
    }

    /// Creates a `ChoiceRow`, which is a reusable view that represents a row in a single/multiple selection list.
    init(
        id: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        isSeparated: Bool = false,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder accessoryIfSelected: @escaping @MainActor () -> AccessoryIfSelected = { EmptyView() }
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isSeparated = isSeparated
        self.action = action
        self.accessoryIfSelected = accessoryIfSelected
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
struct SimpleChoiceRow: View {
    private let id: String
    private let title: String
    private let subtitle: String
    private let isSeparated: Bool
    @Binding private var isSelected: Bool

    var body: some View {
        ChoiceRow(id: id, title: title, subtitle: subtitle, isSelected: isSelected, isSeparated: isSeparated) {
            isSelected.toggle()
        }
    }

    init(id: String, title: String, subtitle: String, isSelected: Binding<Bool>, isSeparated: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self._isSelected = isSelected
        self.isSeparated = isSeparated
    }
}

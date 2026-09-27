//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

import SwiftUI


/// The mark at the end of a row, which says how many rows may be picked: a dot fills the circle the way a radio
/// button does, a checkmark adds up the way Mail and Photos mark a selection.
enum SelectionMark {
    /// A circle that fills. Picking one empties the others.
    case single
    /// A circle that takes a checkmark. Picks add up.
    case multiple

    fileprivate func symbol(selected: Bool) -> String {
        switch (self, selected) {
        case (.single, false), (.multiple, false): "circle"
        case (.single, true): "circle.inset.filled"
        case (.multiple, true): "checkmark.circle.fill"
        }
    }
}


/// A row in a single/multiple choice picker
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChoiceRow<AccessoryIfSelected: View>: View {
    /// The row's identifier; used for the view's UI testing accessibility identifier
    private var id: String
    private let title: String
    private let subtitle: String
    private let isSelected: Bool
    private let isSeparated: Bool
    private let mark: SelectionMark
    private let action: @MainActor () -> Void
    private let accessoryIfSelected: @MainActor () -> AccessoryIfSelected

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the selections, so the mark bounces and the haptic plays on picking, not on clearing.
    @State private var selections = 0

    var body: some View {
        Button {
            if !isSelected {
                selections += 1
            }
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
        .sensoryFeedback(.selection, trigger: selections)
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

    /// Shape as well as colour, so the selection survives a colour-blind reading, and a dot or a
    /// checkmark, so the row says whether it stands alone or adds up.
    private var selectionMark: some View {
        Image(systemName: mark.symbol(selected: isSelected))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            // The mark is the whole confirmation an answer gets, so it is worth seeing arrive, and worth seeing
            // go quickly: the symbol crosses over, and the one just picked swells a touch and settles.
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeOut(duration: isSelected ? 0.16 : 0.08), value: isSelected)
            .phaseAnimator([1.0, 1.12, 1.0], trigger: reduceMotion ? 0 : selections) { view, scale in
                view.scaleEffect(scale)
            } animation: { scale in
                scale > 1 ? .easeOut(duration: 0.1) : .spring(duration: 0.22, bounce: 0.35)
            }
            .accessibilityHidden(true)
    }

    /// Creates a `ChoiceRow`, which is a reusable view that represents a row in a single/multiple selection list.
    init(
        id: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        isSeparated: Bool = false,
        mark: SelectionMark = .single,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder accessoryIfSelected: @escaping @MainActor () -> AccessoryIfSelected = { EmptyView() }
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isSeparated = isSeparated
        self.mark = mark
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

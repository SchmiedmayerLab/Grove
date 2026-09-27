//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import OrderedCollections
import SwiftUI


/// This views renders the sections for the signup or signup-like views.
///
/// The view and it's subviews typically expect the following environment objects:
/// - The global ``Account`` object
/// - The internal `FocusStateObject` to pass down a `FocusState` (for the PersonNameKey implementation).
/// - An instance of ``AccountValuesBuilder`` according to the generic ``AccountValues`` type.
/// - An ``ValidationEngines`` object.
/// - The ``SwiftUI/EnvironmentValues/accountServiceConfiguration`` environment variable.
/// - The ``SwiftUI/EnvironmentValues/accountViewType`` environment variable.
@available(iOS 18, macOS 15, watchOS 11, *)
struct SignupSectionsView: View {
    /// Where the sections render: as `Form` sections, or as cards on an onboarding page.
    enum Layout {
        case form
        case cards
    }

    private let sections: OrderedDictionary<AccountKeyCategory, [any AccountKey.Type]>
    private let layout: Layout

    @Environment(Account.self)
    private var account

    var body: some View {
        switch layout {
        case .form:
            formSections
        case .cards:
            cards
        }
    }

    @ViewBuilder private var formSections: some View {
        // OrderedDictionary `elements` conforms to RandomAccessCollection so we can directly use it
        ForEach(sections.elements, id: \.key) { category, accountKeys in
            Section {
                // the array doesn't change, so its fine to rely on the indices as identifiers
                ForEach(accountKeys.indices, id: \.self) { index in
                    VStack {
                        accountKeys[index].emptyDataEntryView()
                    }
                }
            } header: {
                if let title = category.categoryTitle {
                    Text(title)
                }
            } footer: {
                footer(for: category)
            }
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sections.elements, id: \.key) { category, accountKeys in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = category.categoryTitle {
                        Text(title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                    VStack(spacing: 0) {
                        ForEach(accountKeys.indices, id: \.self) { index in
                            if index > 0 {
                                Divider()
                            }
                            accountKeys[index].emptyDataEntryView()
                                .accountCardRow()
                        }
                    }
                        .accountCard()
                    footer(for: category)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    init(sections: OrderedDictionary<AccountKeyCategory, [any AccountKey.Type]>, layout: Layout = .form) {
        self.sections = sections
        self.layout = layout
    }

    @ViewBuilder private func footer(for category: AccountKeyCategory) -> some View {
        if category == .credentials && account.configuration.password != nil {
            PasswordValidationRuleFooter(configuration: account.accountService.configuration)
        }
    }
}


#if DEBUG
@available(iOS 18, macOS 15, watchOS 11, *)
private let credentials: [any AccountKey.Type] = [
    AccountKeys.userId,
    AccountKeys.password
]

@available(iOS 18, macOS 15, watchOS 11, *)
private let name: [any AccountKey.Type] = [
    AccountKeys.name
]
@available(iOS 18, macOS 15, watchOS 11, *)
#Preview {
    Form {
        SignupSectionsView(sections: [
            .credentials: credentials,
            .name: name
        ])
    }
    .previewWith {
        AccountConfiguration(service: InMemoryAccountService())
    }
}
#endif

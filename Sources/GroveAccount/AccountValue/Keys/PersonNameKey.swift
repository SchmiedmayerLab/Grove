//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GrovePersonalInfo
import GroveValidation
import GroveViews
public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
private struct DisplayView: DataDisplayView {
    private let value: PersonNameComponents

    var body: some View {
        ListRow(AccountKeys.name.name) {
            Text(value.formatted(.name(style: .long)))
        }
    }

    init(_ value: PersonNameComponents) {
        self.value = value
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private struct EntryView: DataEntryView {
    @Environment(Account.self)
    private var account

    @ValidationState private var givenNameValidation
    @ValidationState private var familyNameValidation

    @Binding private var name: PersonNameComponents

    private var nameIsRequired: Bool {
        account.configuration.name?.requirement == .required
    }

    private var validationRule: ValidationRule {
        nameIsRequired ? .nonEmpty : .acceptAll
    }

    var body: some View {
        VStack(spacing: 0) {
            nameRow(for: \.givenName, prompt: Text("UAP_SIGNUP_GIVEN_NAME_PLACEHOLDER", bundle: .module), validation: $givenNameValidation)
            Divider()
            nameRow(for: \.familyName, prompt: Text("UAP_SIGNUP_FAMILY_NAME_PLACEHOLDER", bundle: .module), validation: $familyNameValidation)
        }
            .padding(.vertical, -12)
            .environment(\.validationConfiguration, .considerNoInputAsValid)
    }


    init(_ value: Binding<PersonNameComponents>) {
        self._name = value
    }

    /// A name row marks itself the way a ``VerifiableTextField`` does, so the card or form row around it takes the tint.
    private func nameRow(
        for component: WritableKeyPath<PersonNameComponents, String?>,
        prompt: Text,
        validation: ValidationState.Binding
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NameTextField(name: $name, for: component, prompt: prompt) {
                prompt
            }
                .validate(input: name[keyPath: component] ?? "", rules: validationRule)
                .receiveValidation(in: validation)
            ValidationResultsView(results: validation.wrappedValue.allDisplayedValidationResults)
        }
            .padding(.vertical, 12)
            .reportsBlocking(validation.wrappedValue.isDisplayingValidationErrors)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountDetails {
    /// The name of a user.
    @AccountKey(
        name: LocalizedStringResource("NAME", bundle: .atURL(from: .module)),
        category: .name,
        as: PersonNameComponents.self,
        initial: .empty(PersonNameComponents()),
        displayView: DisplayView.self,
        entryView: EntryView.self
    )
    public var name: PersonNameComponents?
}


@available(iOS 18, macOS 15, watchOS 11, *)
@KeyEntry(\.name)
public extension AccountKeys {} // swiftlint:disable:this no_extension_access_modifier

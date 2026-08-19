//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import GroveFoundation
import GroveValidation
public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
private struct EntryView: DataEntryView {
    @Binding private var email: String

    var body: some View {
        VerifiableTextField(AccountKeys.email.name, text: $email)
            .textContentType(.emailAddress)
            .disableFieldAssistants()
    }

    init(_ value: Binding<String>) {
        self._email = value
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountDetails {
    /// The email address of a user.
    @AccountKey(
        name: LocalizedStringResource("USER_ID_EMAIL", bundle: .atURL(from: .module)),
        category: .contactDetails,
        as: String.self,
        entryView: EntryView.self
    )
    public var email: String?
}


@available(iOS 18, macOS 15, watchOS 11, *)
@KeyEntry(\.email)
public extension AccountKeys {} // swiftlint:disable:this no_extension_access_modifier


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountDetails.__Key_email: OptionalComputedKnowledgeSource {
    public typealias StoragePolicy = AlwaysCompute

    public static func compute(from repository: AccountStorage) -> String? {
        if let email = repository.get(Self.self) {
            // if we have manually stored a value for this key we return it
            return email
        }

        guard let configuration = repository[AccountDetails.AccountServiceConfigurationDetailsKey.self],
              case .emailAddress = configuration.userIdConfiguration.idType else {
            return nil
        }

        // return the userId if it's a email address
        return repository[AccountKeys.userId]
    }
}

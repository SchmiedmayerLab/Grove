//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveAccount
import GroveValidation
import SwiftUI


private struct EntryView: DataEntryView {
    @Binding private var biography: String

    var body: some View {
        VerifiableTextField(AccountKeys.biography.name, text: $biography)
            .autocorrectionDisabled()
    }

    init(_ value: Binding<String>) {
        self._biography = value
    }
}


extension AccountDetails {
    @AccountKey(name: "Biography", category: .personalDetails, as: String.self, entryView: EntryView.self)
    var biography: String?
}


@KeyEntry(\.biography)
extension AccountKeys {}

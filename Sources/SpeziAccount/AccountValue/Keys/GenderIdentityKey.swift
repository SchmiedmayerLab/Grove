//
// This source file is part of the Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 17, macOS 14, *)
extension AccountDetails {
    /// The gender identity of a user.
    ///
    /// ## Topics
    /// - ``GenderIdentity``
    @AccountKey(
        name: LocalizedStringResource("GENDER_IDENTITY_TITLE", bundle: .atURL(from: .module)),
        category: .personalDetails,
        as: GenderIdentity.self,
        initial: .default(.preferNotToState)
    )
    public var genderIdentity: GenderIdentity?
}


@KeyEntry(\.genderIdentity)
@available(iOS 17, macOS 14, *)
public extension AccountKeys {} // swiftlint:disable:this no_extension_access_modifier

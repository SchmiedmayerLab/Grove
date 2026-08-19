//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


@available(iOS 18, macOS 15, watchOS 11, *)
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


@available(iOS 18, macOS 15, watchOS 11, *)
@KeyEntry(\.genderIdentity)
public extension AccountKeys {} // swiftlint:disable:this no_extension_access_modifier

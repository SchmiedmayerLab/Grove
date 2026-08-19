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


extension AccountDetails {
    @AccountKey(name: "Biography", category: .personalDetails, as: String.self)
    var biography: String?
}


@KeyEntry(\.biography)
extension AccountKeys {}

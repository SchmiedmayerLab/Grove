//
// This source file is part of the Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@_spi(TestingSupport)
@available(iOS 17, macOS 14, *)
extension AccountDetails {
    static func createMock(
        id: String = UUID().uuidString,
        userId: String = "lelandstanford@stanford.edu",
        name: PersonNameComponents? = PersonNameComponents(givenName: "Leland", familyName: "Stanford"),
        genderIdentity: GenderIdentity? = nil,
        dateOfBirth: Date? = nil
    ) -> AccountDetails {
        var details = AccountDetails()
        details.accountId = id
        details.userId = userId
        details.name = name
        details.genderIdentity = genderIdentity
        #if !os(tvOS)
        details.dateOfBirth = dateOfBirth
        #endif
        return details
    }
}

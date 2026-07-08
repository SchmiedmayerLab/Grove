//
// This source file is part of the Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// UserId and password-based credentials.
@available(iOS 17, macOS 14, *)
public struct UserIdPasswordCredential {
    /// The user-visible primary identifier.
    public let userId: String
    /// The password
    public let password: String
}


@available(iOS 17, macOS 14, *)
extension UserIdPasswordCredential: Sendable, Hashable, Codable {}

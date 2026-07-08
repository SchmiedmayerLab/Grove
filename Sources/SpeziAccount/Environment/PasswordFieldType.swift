//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// The semantic use of a password field.
@available(iOS 17, macOS 14, *)
public enum PasswordFieldType {
    /// Standard password field
    case password
    /// New password field
    case new
    /// Password repeat field
    case `repeat`
}


@available(iOS 17, macOS 14, *)
extension PasswordFieldType: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .password:
            return AccountKeys.password.name
        case .new:
            return .init("NEW_PASSWORD", bundle: .atURL(from: .module))
        case .repeat:
            return .init("REPEAT_PASSWORD", bundle: .atURL(from: .module))
        }
    }

    public var localizedPrompt: LocalizedStringResource {
        switch self {
        case .password:
            return AccountKeys.password.name
        case .new:
            return .init("NEW_PASSWORD_PROMPT", bundle: .atURL(from: .module))
        case .repeat:
            return .init("REPEAT_PASSWORD_PROMPT", bundle: .atURL(from: .module))
        }
    }
}


@available(iOS 17, macOS 14, *)
extension PasswordFieldType: Sendable, Hashable {}


@available(iOS 17, macOS 14, *)
extension EnvironmentValues {
    private struct PasswordFieldTypeKey: EnvironmentKey {
        static let defaultValue: PasswordFieldType = .password
    }

    /// The semantic use of a password field.
    ///
    /// ## Topics
    ///
    /// - ``PasswordFieldType``
    @Entry public var passwordFieldType: PasswordFieldType = .password
}

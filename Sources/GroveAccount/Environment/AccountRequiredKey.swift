//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


extension EnvironmentValues {
    /// An environment variable that indicates if an account was configured to be required for the app.
    ///
    /// Fore more information have a look at ``SwiftUICore/View/accountRequired(_:accountSetupIsComplete:setupSheet:)``.
    @Entry public var accountRequired: Bool = false
}

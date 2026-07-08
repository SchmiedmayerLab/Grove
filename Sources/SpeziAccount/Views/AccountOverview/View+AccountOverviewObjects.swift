//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


@available(iOS 17, macOS 14, *)
extension View {
    func injectEnvironmentObjects(configuration: AccountServiceConfiguration, model: AccountOverviewFormViewModel) -> some View {
        self
            .environment(\.accountServiceConfiguration, configuration)
            .environment(model.modifiedDetailsBuilder)
    }
}

//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


@available(macOS 26, *)
extension Application {
    /// Access Spezi configuration and modules.
    public var spezi: SpeziVapor {
        SpeziVapor(application: self)
    }
}

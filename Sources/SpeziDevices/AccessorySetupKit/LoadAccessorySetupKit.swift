//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziBluetooth


@available(iOS 18, macOS 15, watchOS 11, *)
final class LoadAccessorySetupKit: Module {
    @Dependency(AccessorySetupKit.self)
    var accessorySetupKit

    init() {}
}

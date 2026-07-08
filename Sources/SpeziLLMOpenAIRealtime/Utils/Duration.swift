//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 17, macOS 14, visionOS 1, *)
extension Duration {
    var milliseconds: Int {
        Int(components.seconds) * 1000 + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}

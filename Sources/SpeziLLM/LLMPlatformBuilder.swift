//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Spezi
import SwiftUI


/// Result builder used to aggregate multiple Spezi ``LLMPlatform``s stated within the ``LLMRunner``.
@resultBuilder
@available(iOS 17, macOS 14, visionOS 1, *)
public enum LLMPlatformBuilder: DependencyCollectionBuilder {
    /// An auto-closure expression, providing the default dependency value, building the `DependencyCollection`.
    public static func buildExpression<L: LLMPlatform>(_ expression: @autoclosure () -> L) -> DependencyCollection {
        DependencyCollection(expression())
    }
}

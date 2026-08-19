//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import Grove
import SwiftUI


/// Result builder used to aggregate multiple Grove ``LLMPlatform``s stated within the ``LLMRunner``.
@available(iOS 18, macOS 15, watchOS 11, *)
@resultBuilder
public enum LLMPlatformBuilder: DependencyCollectionBuilder {
    /// An auto-closure expression, providing the default dependency value, building the `DependencyCollection`.
    public static func buildExpression<L: LLMPlatform>(_ expression: @autoclosure () -> L) -> DependencyCollection {
        DependencyCollection(expression())
    }
}

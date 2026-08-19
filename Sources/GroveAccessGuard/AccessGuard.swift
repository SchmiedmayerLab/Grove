//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// Inspect and interact with a specific access guard.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
@propertyWrapper
public struct AccessGuard<Config: _AccessGuardConfig>: DynamicProperty {
    @Environment(AccessGuards.self) private var accessGuards
    
    let id: AccessGuardIdentifier<Config>
    
    public var wrappedValue: Config._Model {
        accessGuards.model(for: id)
    }
    
    public init(_ id: AccessGuardIdentifier<Config>) {
        self.id = id
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


struct ModuleReference: Hashable, Sendable {
    // periphery:ignore - read by the synthesized Hashable/Equatable conformance
    private let id: ObjectIdentifier

    init(_ module: any Module) {
        self.id = ObjectIdentifier(module)
    }
}


extension Module {
    var reference: ModuleReference {
        ModuleReference(self)
    }
}

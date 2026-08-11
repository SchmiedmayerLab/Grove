//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import OrderedCollections


struct CollectedModuleValues<ModuleValue>: DefaultProvidingKnowledgeSource {
    typealias Anchor = GroveAnchor
    typealias Value = OrderedDictionary<UUID, [ModuleValue]>

    static var defaultValue: Value {
        [:]
    }
}

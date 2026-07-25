//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziVapor
import Testing

actor TestModule2: Module, Sendable {
    var numbers: [Int] = []
}

final class TestModule: Module, Sendable {
    let confirmation: Confirmation?
    
    let userData: [UserData]
    
    init(confirmation: Confirmation? = nil, userData: [UserData] = []) {
        self.confirmation = confirmation
        self.userData = userData
    }
    
    func configure() {
        confirmation?()
    }
    
    func getAllUsers() -> [UserData] {
        userData
    }
    
    func getUser(byId id: Int) -> UserData? {
        userData.first { $0.id == id }
    }
}

//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziVapor
import Testing


@Suite("Data Module Tests", .serialized)
struct DataModuleTests {
    let testUsers = [
        UserData(id: 1, name: "Alice", email: "alice@example.com"),
        UserData(id: 2, name: "Bob", email: "bob@example.com")
    ]

    @Test
    func dataModuleReturnsUsers() async throws {
        try await withSpeziVaporApp(routes: routes, standard: TestStandard(), modules: { TestModule(userData: testUsers) }) { app in
            try await app.testing().test(.GET, "users", afterResponse: { res in
                #expect(res.status == .ok)
                let users = try res.content.decode([UserData].self)
                #expect(users.count == 2)
                #expect(users.contains { $0.id == 1 })
                #expect(users.contains { $0.id == 2 })
            })
        }
    }
    
    @Test
    func dataModuleReturnsUser() async throws {
        try await withSpeziVaporApp(routes: routes, modules: { TestModule(userData: testUsers) }) { app in
            try await app.testing().test(.GET, "users/1", afterResponse: { res in
                #expect(res.status == .ok)
                let user = try res.content.decode(UserData.self)
                #expect(user.id == 1)
                #expect(user.name == "Alice")
                #expect(user.email == "alice@example.com")
            })
        }
    }
    
    @Test
    func dataModuleReturnsUserNotFound() async throws {
        try await withSpeziVaporApp(routes: routes, modules: { TestModule(userData: testUsers) }) { app in
            try await app.testing().test(.GET, "users/999", afterResponse: { res in
                #expect(res.status == .notFound)
            })
        }
    }
}

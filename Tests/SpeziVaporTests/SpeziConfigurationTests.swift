//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import SpeziVapor
import Testing


@Suite("Spezi Vapor Configuration Test", .serialized)
struct SpeziVaporConfigurationTest {
    @Test
    func accessingSpezi() async throws {
        try await withSpeziVaporApp(standard: TestStandard(), modules: { TestModule() }) { app in
            #expect(Optional(app.spezi.spezi) != nil)
        }
    }
    
    @Test
    func moduleConfigureIsCalled() async throws {
        try await confirmation { confirmation in
            try await withSpeziVaporApp(standard: TestStandard(), modules: { TestModule(confirmation: confirmation) }) { _ in }
        }
    }
    
    @Test
    func accessingConfiguredModule() async throws {
        let testModule = TestModule()
        try await withSpeziVaporApp(standard: TestStandard(), modules: { testModule }) { app in
            #expect(app.spezi[TestModule.self] === testModule)
            #expect(app.spezi[TestModule?.self] === testModule)
        }
    }
    
    @Test
    func accessingUnconfiguredModule() async throws {
        await #expect(processExitsWith: .failure) {
            try await withSpeziVaporApp(standard: TestStandard(), modules: {}) { app in
                #expect(app.spezi[TestModule?.self] == nil)
                _ = app.spezi[TestModule.self]
            }
        }
    }
}

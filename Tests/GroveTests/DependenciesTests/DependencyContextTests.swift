//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import Testing

private final class ExampleModule: Module {}

#if os(macOS)
@Suite(.serialized)
struct DependencyContextTests {
    @Test
    func injectionPreconditionDependencyPropertyWrapper() async throws {
        let result = try await #require(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            _ = _DependencyPropertyWrapper<TestModule>(wrappedValue: TestModule(), TestModule.self).wrappedValue
        }

        let standardError = String(decoding: result.standardErrorContent, as: UTF8.self)
        #expect(standardError.contains("A `@Dependency` was accessed before the dependency was activated."))
    }

    @Test
    func injectionPreconditionDynamicDependenciesPropertyWrapper() async throws {
        let result = try await #require(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            _ = _DependencyPropertyWrapper {
                ExampleModule()
            }.wrappedValue
        }

        let standardError = String(decoding: result.standardErrorContent, as: UTF8.self)
        #expect(standardError.contains("A `@Dependency` was accessed before the dependency was activated."))
    }
}
#endif

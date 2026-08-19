//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@testable import Grove
import Testing

@Suite(.serialized)
struct StandardInjectionTests {
    final class StandardInjectionTestModule: Module {
        @StandardActor var standard: MockStandard
        
        let expectation: TestExpectation
        
        
        init(expectation: TestExpectation) {
            self.expectation = expectation
        }
        
        
        func configure() {
            Task {
                await standard.fulfill(expectation: expectation)
            }
        }
    }
    
#if canImport(SwiftUI)
    class StandardInjectionTestApplicationDelegate: GroveAppDelegate {
        let expectation: TestExpectation
        
        
        override var configuration: Configuration {
            Configuration(standard: MockStandard()) {
                StandardInjectionTestModule(expectation: expectation)
            }
        }
        
        
        init(expectation: TestExpectation) {
            self.expectation = expectation
        }
    }
    
    @Test
    func moduleFlow() async throws {
        let expectation = TestExpectation()
        
        let standardInjectionTestApplicationDelegate = await StandardInjectionTestApplicationDelegate(
            expectation: expectation
        )
        _ = await standardInjectionTestApplicationDelegate.grove
        
        await expectation.fulfillment(within: .seconds(5))
    }
#endif
    
#if os(macOS)
    @Test
    func injectionPrecondition() async throws {
        let result = try await #require(
            processExitsWith: .failure,
            observing: [\.standardErrorContent]
        ) {
            _ = _StandardPropertyWrapper<MockStandard>().wrappedValue
        }

        let standardError = String(decoding: result.standardErrorContent, as: UTF8.self)
        #expect(standardError.contains("`_StandardPropertyWrapper`'s wrappedValue was accessed before"))
    }
#endif
}

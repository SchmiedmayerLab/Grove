//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(APISupport) @testable import Grove
#if canImport(Observation) && canImport(SwiftUI)
import Observation
#endif
import GroveTesting
#if canImport(SwiftUI)
import SwiftUI
#endif
import Testing


private final class DependingTestModule: Module {
    let confirmation: Confirmation?
    @Dependency var module = TestModule()


    init(confirmation: Confirmation? = nil, dependencyConfirmation: Confirmation? = nil) {
        self.confirmation = confirmation
        self._module = Dependency(wrappedValue: TestModule(confirmation: dependencyConfirmation))
    }


    func configure() {
        self.confirmation?()
    }
}


@MainActor
@Suite("Module", .serialized)
struct ModuleTests {
#if canImport(SwiftUI)
    @Test("Module Flow")
    func moduleFlow() async {
        await confirmation { confirmation in
            _ = Text("Grove")
                .grove(TestApplicationDelegate(confirmation: confirmation))
        }
    }
#endif

    @Test("Grove")
    func grove() throws {
        let grove = Grove(standard: DefaultStandard(), modules: [DependingTestModule()])

        let modules = grove.modules
        #expect(modules.count == 3)
        #expect(modules.contains(where: { $0 is DefaultStandard }))
        #expect(modules.contains(where: { $0 is DependingTestModule }))
        #expect(modules.contains(where: { $0 is TestModule }))
    }

#if canImport(Observation) && canImport(SwiftUI)
    @available(macOS 14, iOS 17, tvOS 17, watchOS 10, visionOS 1, *)
    @Test("Storage Mutations Remain Observable")
    func storageMutationsRemainObservable() async {
        let grove = Grove(standard: DefaultStandard(), modules: [])
        let observation = TestExpectation()

        withObservationTracking {
            _ = grove.modules
        } onChange: {
            observation.fulfill()
        }

        grove.loadModule(TestModule())
        await observation.fulfillment(within: .seconds(1))
    }
#endif

#if canImport(SwiftUI)
    @Test("Preview Modifier")
    func previewModifier() async throws {
        // manually patch environment variable for running within Xcode preview window
        setenv(ProcessInfo.xcodeRunningForPreviewKey, "1", 1)

        await confirmation { confirmation in
            _ = Text("Grove")
                .previewWith {
                    TestModule(confirmation: confirmation)
                }
        }

        unsetenv(ProcessInfo.xcodeRunningForPreviewKey)
    }
#endif

    @Test("Module Creation")
    func moduleCreation() async {
        await confirmation { moduleConfirmation in
            await confirmation { dependencyConfirmation in
                let module = DependingTestModule(confirmation: moduleConfirmation, dependencyConfirmation: dependencyConfirmation)

                withDependencyResolution {
                    module
                }


                _ = module.module
            }
        }
    }
}

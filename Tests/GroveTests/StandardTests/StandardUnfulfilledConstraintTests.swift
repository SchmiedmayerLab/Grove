//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(APISupport) @testable import Grove
import Testing


private protocol UnfulfilledExampleConstraint: Standard {
    func thisFunctionWouldBeNice()
}


@MainActor
@Suite(.serialized)
struct StandardUnfulfilledConstraintTests {
    final class StandardUCTestModule: Module {
        @StandardActor private var standard: any UnfulfilledExampleConstraint

        func configure() {
            Task {
                await standard.thisFunctionWouldBeNice()
            }
        }
    }

    @Test
    func standardUnfulfilledConstraint() throws {
        let configuration = Configuration(standard: MockStandard()) {}
        let grove = Grove(from: configuration)
        #expect {
            try grove.loadModules([StandardUCTestModule()], ownership: .grove)
        } throws: { error in
            guard let moduleError = error as? GroveModuleError,
                  case let .property(propertyError) = moduleError,
                  case let .unsatisfiedStandardConstraint(constraint, standard) = propertyError else {
                Issue.record("Encountered unexpected error: \(error)")
                return false
            }
            #expect(constraint == "UnfulfilledExampleConstraint")
            #expect(standard == "MockStandard")
            return true
        }
    }
}

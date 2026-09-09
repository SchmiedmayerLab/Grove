//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveHealthKit
import SwiftUI


@main
struct UITestsApp: App {
    @UIApplicationDelegateAdaptor private var delegate: TestAppDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .grove(delegate)
        }
    }
}


final class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestAppStandard()) {
            HealthKit()
        }
    }
}


actor TestAppStandard: Standard, HealthKitConstraint {
    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) -> HealthKitAnchorCommitAction? {
        nil
    }
    
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) -> HealthKitAnchorCommitAction? {
        nil
    }
}

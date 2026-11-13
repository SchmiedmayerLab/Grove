//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import HealthKit
public import XCTest


extension XCTestCase {
    /// Launches the Health app and adds the specified sample to the database.
    @MainActor
    public func launchAndAddSample(
        healthApp: XCUIApplication = .healthApp,
        _ sample: NewHealthSampleInput
    ) throws {
        try launchAndAddSamples(healthApp: healthApp, CollectionOfOne(sample))
    }
    
    /// Launches the Health app and adds the specified samples to the database.
    @MainActor
    public func launchAndAddSamples(
        healthApp: XCUIApplication = .healthApp,
        _ samples: some Collection<NewHealthSampleInput>
    ) throws {
        try healthApp.assertIsHealthApp()
        // Note that we intentionally use launch here, rather than activate.
        // This will ensure that we have a fresh instance of the app, and we won't have to deal with any sheets
        // or other modals potentially being presented.
        // There might still be some state restoration going on (eg: the Health app will sometimes navigate to the last-used
        // page w/in one of the tabs), but that's easy to handle.
        healthApp.launch()
        XCTAssert(healthApp.wait(for: .runningForeground, timeout: 30))

        // Handle onboarding, if necessary
        handleHealthAppOnboardingIfNecessary(healthApp)
        
        try healthApp.goToBrowseTab()
        
        let samplesByCategory = Dictionary(grouping: samples, by: \.sampleType.category)
        for (category, samples) in samplesByCategory {
            try category.navigateToPage(in: healthApp)
            let samplesBySampleType = Dictionary(grouping: samples, by: \.sampleType)
            for (sampleType, samples) in samplesBySampleType {
                try sampleType.navigateToPage(in: healthApp, assumeAlreadyInCategory: true)
                for sample in samples {
                    try sample.create(in: healthApp)
                }
            }
        }
    }
}


extension XCUIApplication {
    /// Attempts to navigate the Health app to the tab listing the health categories: "Browse" before iOS 26 and again from
    /// iOS 27, "Search" on iOS 26.
    ///
    /// - Note: This function expects that no modals or sheets are currently presented.
    @MainActor
    public func goToBrowseTab() throws {
        if XCTestCase.isIOS27OrGreater {
            try goToBrowseTabOnIOS27()
        } else if XCTestCase.isIOS26OrGreater {
            try assertIsHealthApp()
            if self.navigationBars["Search"].exists {
                return
            }
            let searchTabBarButton = self.tabBars.buttons["Search"]
            guard searchTabBarButton.wait(for: \.isHittable, toEqual: true, timeout: 10) else {
                if dismissAccountSheetIfNecessary() {
                    try goToBrowseTab()
                    return
                } else {
                    throw XCTHealthKitError("Unable to find 'Search' tab bar item")
                }
            }
            searchTabBarButton.tap() // select the tab
            if searchTabBarButton.wait(for: \.isHittable, toEqual: true, timeout: 2) {
                searchTabBarButton.tap() // go back to the tab's root VC, if necessary
            }
        } else {
            let browseTabBarButton = self.tabBars["Tab Bar"].buttons["Browse"]
            guard browseTabBarButton.wait(for: \.isHittable, toEqual: true, timeout: 2) else {
                throw XCTHealthKitError("Unable to find 'Browse' tab bar item")
            }
            browseTabBarButton.tap() // select the tab
            XCTAssert(browseTabBarButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
            browseTabBarButton.tap() // go back to the tab's root VC, if necessary
        }
    }
    
    @MainActor
    private func goToBrowseTabOnIOS27() throws {
        try assertIsHealthApp()
        if self.navigationBars["Browse"].exists {
            return
        }
        let browseTabBarButton = self.tabBars.buttons["UIA.Health.Tab.Browse"]
        guard browseTabBarButton.wait(for: \.isHittable, toEqual: true, timeout: 10) else {
            if dismissAccountSheetIfNecessary() {
                try goToBrowseTab()
                return
            } else {
                throw XCTHealthKitError("Unable to find 'Browse' tab bar item")
            }
        }
        browseTabBarButton.tap() // select the tab
        if !self.navigationBars["Browse"].waitForExistence(timeout: 2) {
            browseTabBarButton.tap() // go back to the tab's root VC, if necessary
        }
    }

    /// - returns: `true` if the account sheet was dismissed, otherwise false.
    @MainActor
    func dismissAccountSheetIfNecessary() -> Bool {
        // From iOS 27 the sheet closes with an "x" button, labelled "close".
        let closeButton = self.navigationBars["HealthExperienceUI.ProfileView"].buttons[XCTestCase.isIOS27OrGreater ? "close" : "Done"]
        if closeButton.exists {
            XCTAssert(closeButton.wait(for: \.isHittable, toEqual: true, timeout: 2))
            closeButton.tap()
            XCTAssert(closeButton.waitForNonExistence(timeout: 2))
            return true
        } else {
            return false
        }
    }
}

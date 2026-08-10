//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
import XCTestApp


enum TestAppTestCaseEnum: String, TestAppTests {
    case xcTestApp = "XCTestApp"
    case textEntry = "Text Entry"
    case dismissKeyboard = "DismissKeyboard"
    case healthKitDataEntry = "HealthKitDataEntry"
    case togglesAndSwitches = "Toggles / Switches"
    
    func view(withNavigationPath path: Binding<NavigationPath>) -> some View {
        switch self {
        case .xcTestApp:
            TestAppView(testCase: XCTestAppTestCaseTest())
        case .textEntry:
            TextEntryTestView()
        case .dismissKeyboard:
            DismissKeyboardTest()
        case .healthKitDataEntry:
            HealthKitDataEntryView()
        case .togglesAndSwitches:
            TogglesAndSwitches()
        }
    }
}

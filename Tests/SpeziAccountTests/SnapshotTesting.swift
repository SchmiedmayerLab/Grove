//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

import SnapshotTesting
@_spi(_Testing)
@_spi(TestingSupport)
@testable import SpeziAccount
import SpeziTesting
import SwiftUI
import Testing


@Suite(
    "iOS Snapshot tests",
    .disabled("""
        Disabled because the Text Fields don't render in the snapshots anymore,
        and we'd need a host application be present in order to be able to set
        `drawHierarchyInKeyWindow: true` in the .image() calls.
        """)
)
struct SnapshotTesting {
    @MainActor
    @Test
    func testBoolDisplayView() {
        let viewTrue = BoolDisplayView<MockBoolKey>(true)
        let viewFalse = BoolDisplayView<MockBoolKey>(false)
        let viewTrueYes = BoolDisplayView<MockBoolKey>(label: .yesNo, true)
        let viewFalseNo = BoolDisplayView<MockBoolKey>(label: .yesNo, false)
        assertSnapshot(of: viewTrue, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-viewTrue")
        assertSnapshot(of: viewFalse, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-viewFalse")
        assertSnapshot(of: viewTrueYes, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-viewTrueYes")
        assertSnapshot(of: viewFalseNo, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-viewFalseNo")
    }
    
    @MainActor
    @Test
    func testIntegerDisplayView() {
        let integer = FixedWidthIntegerDisplayView<MockNumericKey>(34)
        let integerWithUnit = FixedWidthIntegerDisplayView<MockNumericKey>(34, unit: Text(verbatim: " cm"))
        assertSnapshot(of: integer, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-integer")
        assertSnapshot(of: integerWithUnit, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-integerWithUnit")
    }
    
    @MainActor
    @Test
    func testFloatingPointDisplayView() {
        let float = FloatingPointDisplayView<MockDoubleKey>(23.56)
        let floatWithUnit = FloatingPointDisplayView<MockDoubleKey>(223.56, unit: Text(verbatim: " cm"))
        assertSnapshot(of: float, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-float")
        assertSnapshot(of: floatWithUnit, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-floatWithUnit")
    }

    @MainActor
    @Test
    func testStringDisplayView() {
        let view = StringDisplayView(\.userId, "Hello World")
        assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone")
    }

    @MainActor
    @Test
    func testLocalizedStringDisplayView() {
        let view = LocalizableStringDisplayView(\.genderIdentity, .male)
        assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone")
    }

    
    @MainActor
    @Test
    func testAccountProviderViewLayoutVariations() {
        let configuration = AccountConfiguration(service: InMemoryAccountService())
        withDependencyResolution {
            configuration
        }

        let view0 = AccountSetupProviderView { _ in
        } signup: { _ in
        } resetPassword: { _ in
        }
            .environment(configuration.account)

        let view1 = AccountSetupProviderView { _ in
        } signup: { _ in
        }
            .environment(configuration.account)

        let view2 = AccountSetupProviderView { (_: UserIdPasswordCredential) in
        } resetPassword: { _ in
        }
            .environment(configuration.account)

        let view3 = AccountSetupProviderView { (_: AccountDetails) in
        } resetPassword: { _ in
        }
            .environment(configuration.account)

        let view4 = AccountSetupProviderView { (_: UserIdPasswordCredential) in
        }
            .environment(configuration.account)

        let view5 = AccountSetupProviderView { (_: AccountDetails) in
        }
            .environment(configuration.account)


        let view0Signup = view0.preferredAccountSetupStyle(.signup)
        let view1Signup = view1.preferredAccountSetupStyle(.signup)
        let view2Signup = view2.preferredAccountSetupStyle(.signup)
        let view3Signup = view3.preferredAccountSetupStyle(.signup)
        let view4Signup = view4.preferredAccountSetupStyle(.signup)
        let view5Signup = view5.preferredAccountSetupStyle(.signup)

        assertSnapshot(of: view0, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view0")
        assertSnapshot(of: view1, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view1")
        assertSnapshot(of: view2, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view2")
        assertSnapshot(of: view3, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view3")
        assertSnapshot(of: view4, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view4")
        assertSnapshot(of: view5, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view5")

        assertSnapshot(of: view0Signup, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view0-signup")
        assertSnapshot(of: view1Signup, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view1-signup")
        assertSnapshot(of: view2Signup, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view2-signup")
        assertSnapshot(of: view3Signup, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view3-signup")
        assertSnapshot(of: view4Signup, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view4-signup")
        assertSnapshot(of: view5Signup, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone-view5-signup")
    }
    
    @MainActor
    @Test
    func testAccountHeader() {
        let configuration = AccountConfiguration(service: InMemoryAccountService())
        withDependencyResolution {
            configuration
        }
        let view = AccountHeader(caption: "Custom Caption")
            .environment(configuration.account)

        assertSnapshot(of: view, as: .image(layout: .device(config: .iPhone13Pro)), named: "iphone")
    }
}

#endif

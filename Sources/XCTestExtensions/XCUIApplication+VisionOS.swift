//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import XCTest

// Use `xcrun simctl spawn booted launchctl list` to check for all bundle identifiers running on visionOS simulator.
// If you are in search for an application bundle identifier you have a good chance of finding it there.


extension XCUIApplication {
    /// Get access to the visionOS keyboard application.
    @available(macOS, unavailable)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @available(visionOS 1, *)
    public static var visionOSKeyboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.RealityKeyboard")
    }

    /// Get access to the visionOS keyboard application.
    @available(macOS, unavailable)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @available(visionOS 1, *)
    public var visionOSKeyboard: XCUIApplication {
        Self.visionOSKeyboard
    }
}


extension XCUIApplication {
    /// Get access to the visionOS notifications application.
    ///
    /// This is the applications that is responsible for drawing all
    @available(macOS, unavailable)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @available(visionOS 1, *)
    public static var visionOSNotifications: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.RealityNotifications")
    }

    /// Get access to the visionOS notifications application.
    ///
    /// This is the applications that is responsible for drawing all
    @available(macOS, unavailable)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @available(visionOS 1, *)
    public var visionOSNotifications: XCUIApplication {
        Self.visionOSNotifications
    }
}

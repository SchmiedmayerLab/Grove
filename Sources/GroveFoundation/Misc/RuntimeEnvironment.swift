//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
#if os(macOS) || targetEnvironment(macCatalyst)
private import Security
#endif


extension ProcessInfo {
    /// Whether the application is currently running in a sandbox.
    ///
    /// This value will always be `true` when running on iOS, watchOS, visionOS, or tvOS.
    public static let isRunningInSandbox: Bool = {
    #if !(os(macOS) || targetEnvironment(macCatalyst))
        // If we're not running on macOS or macCatalyst, we're running on iOS/watchOS/visionOS/tvOS which always have a sandbox
        return true
    #else
        var `self`: SecCode?
        guard SecCodeCopySelf([], &self) == errSecSuccess else {
            return false
        }
        var codeSignInfo: CFDictionary?
        guard SecCodeCopySigningInformation(
            unsafeBitCast(self, to: SecStaticCode.self),
            SecCSFlags(rawValue: kSecCSDynamicInformation),
            &codeSignInfo
        ) == errSecSuccess else {
            return false
        }
        guard let codeSignInfo = codeSignInfo.map({ $0 as NSDictionary }),
              let entitlementsDict = codeSignInfo[kSecCodeInfoEntitlementsDict] as? NSDictionary else {
            return false
        }
        if let sandboxEntry = entitlementsDict["com.apple.security.app-sandbox"] as? NSNumber {
            return sandboxEntry.boolValue
        } else {
            return false
        }
    #endif
    }()
    
    
    /// Whether the application or library is currently being unit-tested.
    ///
    /// - Note: This value does **not** always indicate whether the application is currently being tested; for example, it will be `false` for an app currently being UI-tested,
    /// since in that case the app itself will be running in a separate process from the actual test target (for which this value would be `true`).
    public static var isRunningInXCTest: Bool {
        // any of the well-known XCTest environment variables exists.
        if ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains(where: { key in
            ProcessInfo.processInfo.environment[key] != nil
        }) {
            return true
        }
        // .xctest bundle loaded (XCTest on macOS, swift-testing via helper on macOS)
        if Bundle.allBundles.contains(where: { $0.isLoaded && $0.bundlePath.hasSuffix(".xctest") }) {
            return true
        }
        // Binary-name-based lookup
        let binaryName = Bundle.main.executableURL?.lastPathComponent ?? ""
        switch binaryName {
        case "xctest", "swiftpm-testing-helper": // macOS XCTest/`swift test` runner
            return true
        default:
            return binaryName.hasSuffix("PackageTests") // Linux / pure executable
                || binaryName.hasSuffix(".xctest") // iOS-style bundle exec
        }
    }
}

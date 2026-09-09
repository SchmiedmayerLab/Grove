//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

import Foundation


/// Product identity of the application performing a HealthKit-to-FHIR conversion.
public struct HealthKitApplication: Hashable, Sendable {
    /// The identity of the running application, read from its main bundle.
    ///
    /// A host without a bundle identifier — a command-line tool, a bare test runner — has no
    /// application identity to state. Rather than trap in a default argument, this yields an
    /// identity that conversion rejects as ``HealthKitConversionError/invalidConverterApplication(_:)``,
    /// so such a host fails through the same typed path as any other invalid context.
    public static var main: HealthKitApplication {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let identifier = bundle.bundleIdentifier ?? ""
        let name = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? identifier
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        return HealthKitApplication(
            name: name,
            bundleIdentifier: identifier,
            version: version,
            build: info["CFBundleVersion"] as? String
        )
    }

    public let name: String
    public let bundleIdentifier: String
    /// The marketing version, alone. A build that produced the resource is ``build``.
    public let version: String
    public let build: String?

    public init(
        name: String,
        bundleIdentifier: String,
        version: String,
        build: String? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
    }
}

#endif

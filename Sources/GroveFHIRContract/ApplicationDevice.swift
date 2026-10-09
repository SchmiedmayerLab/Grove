//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// The converting application, as the immutable application Device snapshot states it.
public struct ApplicationDevice: Hashable, Sendable {
    /// Why the stated application is not one a Device snapshot can name.
    public enum ValidationError: Error, Equatable, Sendable {
        case blankName
        case invalidBundleIdentifier(String)
        case blankVersion
        case blankBuild
    }

    public let name: String
    public let bundleIdentifier: String
    /// The marketing version alone; the build that produced the resource is ``build``.
    public let version: String
    public let build: String?

    /// The token the application's event-scoped Device snapshot identity is minted from:
    /// `<bundle identifier>|<version>`, then `|<build>` when the application states one.
    public var sourceDeviceToken: String {
        Self.sourceDeviceToken(bundleIdentifier: bundleIdentifier, version: version, build: build)
    }

    public init(
        name: String,
        bundleIdentifier: String,
        version: String,
        build: String? = nil
    ) throws(ValidationError) {
        guard !name.isBlank else {
            throw .blankName
        }
        guard Self.isValidBundleIdentifier(bundleIdentifier) else {
            throw .invalidBundleIdentifier(bundleIdentifier)
        }
        guard !version.isBlank else {
            throw .blankVersion
        }
        guard build?.isBlank != true else {
            throw .blankBuild
        }
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
    }

    /// The identity a bundle states about itself.
    ///
    /// A host without a bundle identifier, such as a bare test runner, has no application identity
    /// to state and fails here rather than inside a conversion.
    public init(bundle: Foundation.Bundle) throws(ValidationError) {
        let info = bundle.infoDictionary ?? [:]
        let identifier = bundle.bundleIdentifier ?? ""
        try self.init(
            name: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? identifier,
            bundleIdentifier: identifier,
            version: info["CFBundleShortVersionString"] as? String ?? "0",
            build: info["CFBundleVersion"] as? String
        )
    }

    /// The snapshot token of an application that states these facts; every application snapshot in a graph, the
    /// writer a questionnaire response names included, is minted from it.
    package static func sourceDeviceToken(bundleIdentifier: String, version: String, build: String?) -> String {
        [bundleIdentifier, version, build].compactMap(\.self).joined(separator: "|")
    }

    /// Apple's bundle-identifier grammar: dot-separated, nonempty ASCII alphanumeric or hyphen labels.
    package static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("."), !value.hasSuffix("."), !value.contains("..") else {
            return false
        }
        return value.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E }
    }
}

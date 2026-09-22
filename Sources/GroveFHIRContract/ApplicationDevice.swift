//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


public enum ApplicationDeviceError: Error, Equatable, Sendable {
    case blankName
    case invalidBundleIdentifier(String)
    case blankVersion
    case blankBuild
}


/// The converting application, as the immutable application Device snapshot states it.
public struct ApplicationDevice: Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    /// The marketing version alone; the build that produced the resource is ``build``.
    public let version: String
    public let build: String?

    public init(
        name: String,
        bundleIdentifier: String,
        version: String,
        build: String? = nil
    ) throws(ApplicationDeviceError) {
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
    public init(bundle: Foundation.Bundle) throws(ApplicationDeviceError) {
        let info = bundle.infoDictionary ?? [:]
        let identifier = bundle.bundleIdentifier ?? ""
        try self.init(
            name: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? identifier,
            bundleIdentifier: identifier,
            version: info["CFBundleShortVersionString"] as? String ?? "0",
            build: info["CFBundleVersion"] as? String
        )
    }

    /// Apple's bundle-identifier grammar: dot-separated, nonempty ASCII alphanumeric or hyphen labels.
    package static func isValidBundleIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("."), !value.hasSuffix("."), !value.contains("..") else {
            return false
        }
        return value.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x2E }
    }
}


extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

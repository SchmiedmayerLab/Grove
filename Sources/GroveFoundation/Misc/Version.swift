//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A `Version` type that implements version 2.0.0 of the [SemVer](https://semver.org/) specification.
///
/// ## Topics
/// ### Creating a Version
/// - ``init(_:_:_:)``
/// - ``init(_:_:_:prereleaseIdentifiers:buildMetadata:)``
/// - ``init(_:)-(OperatingSystemVersion)``
/// - ``init(stringLiteral:)``
///
/// ### Instance Properties
/// - ``major``
/// - ``minor``
/// - ``patch``
/// - ``prereleaseIdentifiers``
/// - ``buildMetadata``
///
/// ### Inspecting a Version
/// - ``isPrereleaseVersion``
///
/// ### Comparing Versions
/// - ``<(_:_:)``
/// - ``==(_:_:)``
///
/// ### Encoding and Decoding Versions
/// - ``init(from:)``
/// - ``encode(to:)``
public struct Version: Hashable, Sendable {
    /// Major version component
    public let major: UInt
    /// Minor version component
    public let minor: UInt
    /// Patch version component
    public let patch: UInt
    /// Pre-release information component. Optional.
    public let prereleaseIdentifiers: [String]
    /// Build metadata component. Optional.
    public let buildMetadata: [String]
    
    /// Creates a new `Version`, using the specified components
    ///
    /// > Note: This initializer will set both `prereleaseIdentifiers` and `buildMetadata` to `[]`.
    ///
    /// - parameter major: The major component of the version
    /// - parameter minor: The minor component of the version
    /// - parameter patch: The patch component of the version
    @inlinable
    public init(_ major: UInt, _ minor: UInt, _ patch: UInt) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = []
        self.buildMetadata = []
    }
    
    /// Creates a new `Version`, using the specified components
    ///
    /// This initializer will validate the elements in `prereleaseIdentifiers` and `buildMetadata`.
    /// Only ASCII strings consisting of letters, numbers, or hyphens are permitted. (I.e., `0-9A-Za-z`.)
    ///
    /// - parameter major: The major component of the version
    /// - parameter minor: The minor component of the version
    /// - parameter patch: The patch component of the version
    /// - parameter prereleaseIdentifiers: Array of pre-release identifiers
    /// - parameter buildMetadata: Array of build metadata identifiers
    @_disfavoredOverload
    public init(_ major: UInt, _ minor: UInt, _ patch: UInt, prereleaseIdentifiers: [String] = [], buildMetadata: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        func isValidIdentifier(_ string: String) -> Bool {
            string.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        precondition(prereleaseIdentifiers.allSatisfy(isValidIdentifier))
        precondition(buildMetadata.allSatisfy(isValidIdentifier))
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadata = buildMetadata
    }
    
    #if canImport(Darwin)
    /// Creates a new `Version` from an `OperatingSystemVersion`.
    @inlinable
    public init(_ other: OperatingSystemVersion) {
        guard let major = UInt(exactly: other.majorVersion),
              let minor = UInt(exactly: other.minorVersion),
              let patch = UInt(exactly: other.patchVersion) else {
            preconditionFailure("'\(other)' contained negative components")
        }
        self.init(major, minor, patch)
    }
    #endif
}


extension Version {
    /// Whether this is a pre-release version, determined based on the existence of e.g. a `-alpha` or `-x.y.z` suffix.
    @inlinable public var isPrereleaseVersion: Bool {
        !prereleaseIdentifiers.isEmpty
    }
}


extension Version: Equatable, Comparable {
    /// Compares two ``Version``s for equality, based on the rules defined in the [SemVer 2.0.0 specification](https://semver.org/#spec-item-11)
    @inlinable
    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(lhs > rhs)
    }
    
    /// Compares two ``Version``s for precedence, based on the rules defined in the [SemVer 2.0.0 specification](https://semver.org/#spec-item-11)
    public static func < (lhs: Version, rhs: Version) -> Bool { // swiftlint:disable:this cyclomatic_complexity
        // all lines prefixed with `> ` are quoting from version 2 of the SemVer spec.
        // > Precedence MUST be calculated by separating the version into major, minor, patch and pre-release identifiers in that order (Build metadata does not figure into precedence).
        // > Precedence is determined by the first difference when comparing each of these identifiers from left to right as follows: Major, minor, and patch versions are always compared numerically.
        guard (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch) else {
            return lhs.major < rhs.major
                || lhs.major <= rhs.major && lhs.minor < rhs.minor
                || lhs.major <= rhs.major && lhs.minor <= rhs.minor && lhs.patch < rhs.patch
        }
        // > When major, minor, and patch are equal, a pre-release version has lower precedence than a normal version:
        switch (lhs.isPrereleaseVersion, rhs.isPrereleaseVersion) {
        case (false, false):
            // neither lhs nor rhs are pre-release versions, and all lhs components until now have compared equal to their respective rhs components
            // --> lhs does not precede rhs (they are equal)
            return false
        case (true, false):
            // lhs is a pre-release component, but rhs is not, and all lhs components until now have compared equal to their respective rhs components
            // --> lhs predeced rhs
            return true
        case (false, true):
            // lhs is not a pre-release component, but rhs is, and all lhs components until now have compared equal to their respective rhs components
            // --> lhs does not predede rhs
            return false
        case (true, true):
            // > Precedence for two pre-release versions with the same major, minor, and patch version MUST be determined by comparing each dot separated identifier from left to right until a difference is found as follows:
            // 1. Identifiers consisting of only digits are compared numerically.
            // 2. Identifiers with letters or hyphens are compared lexically in ASCII sort order.
            // 3. Numeric identifiers always have lower precedence than non-numeric identifiers.
            // 4. A larger set of pre-release fields has a higher precedence than a smaller set, if all of the preceding identifiers are equal.
            for (lhs, rhs) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
                guard lhs != rhs else {
                    // if the identifiers are equal, we continue the loop.
                    // since this is the only place in the loop where we don't return,
                    // we can assume that we only end up outside of the loop in the case that all zipped lhs/rhs pairs were equal.
                    continue
                }
                return switch (UInt(lhs), UInt(rhs)) {
                // > 1. Identifiers consisting of only digits are compared numerically.
                case let (.some(lhs), .some(rhs)):
                    lhs < rhs
                // > 2. Identifiers with letters or hyphens are compared lexically in ASCII sort order.
                case (.none, .none):
                    !lhs.lexicographicallyPrecedes(lhs)
                // 3. Numeric identifiers always have lower precedence than non-numeric identifiers.
                case (.some, .none):
                    true // lhs is numeric --> it has precedence
                case (.none, .some):
                    false // rhs is numeric --> it has precedence
                }
            }
            // all pre-release identifiers until now have compared equal.
            assert(zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers).allSatisfy { $0 == $1 })
            // > 4. A larger set of pre-release fields has a higher precedence than a smaller set, if all of the preceding identifiers are equal.
            return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Version: LosslessStringConvertible {
    public var description: String {
        var desc = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            desc += "-"
            desc += prereleaseIdentifiers.joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            desc += "+"
            desc += buildMetadata.joined(separator: ".")
        }
        return desc
    }
    
    /// Attempts to create a ``Version` by parsing a `String`.
    public init?(_ description: String) {
        // swiftlint:disable:next line_length
        let pattern = /^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]+)(?<prerelease>-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(?<buildMetadata>\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/
        guard let match = try? pattern.wholeMatch(in: description) else {
            return nil
        }
        guard let major = UInt(match.output.major),
              let minor = UInt(match.output.minor),
              let patch = UInt(match.output.patch) else {
            return nil
        }
        self.init(
            major,
            minor,
            patch,
            prereleaseIdentifiers: match.output.prerelease?.dropFirst().components(separatedBy: ".") ?? [],
            buildMetadata: match.output.buildMetadata?.dropFirst().components(separatedBy: ".") ?? []
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Version: ExpressibleByStringLiteral {
    /// Attempts to create a ``Version`` by parsing a `String` literal.
    ///
    /// - Note: The compiler will prefer this function over `Version.init(_:)` when calling e.g. `Version("1.2.3")`.
    ///     If you want to call the failible initializer with a `String` literal, you need to add an explicit `init` call: `Version.init("1.2.3")`.
    ///     This is not applicable if the parameter is a non-literal expression of type `String`.
    public init(stringLiteral value: String) {
        guard let version = Version(value) else {
            preconditionFailure("String literal '\(value)' does not represent a valid \(Version.self)")
        }
        self = version
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Version: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        if let version = Self(string) {
            self = version
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "String did not encode a valid Version"
            ))
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

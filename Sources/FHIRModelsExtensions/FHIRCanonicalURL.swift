//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// A current FHIR canonical URL.
///
/// ```swift
/// static let itemControl = FHIRCanonicalURL(
///     "https://grovealliance.org/fhir/questionnaire/CodeSystem/grove-questionnaire-item-control"
/// )
/// ```
///
/// Deliberately backed by `String` rather than `URL`: the questionnaire read sites compile at the
/// package's lowest deployment target, below the availability of the `URL`-typed helpers.
///
/// ## Topics
///
/// ### Creating an Identifier
/// - ``init(_:)``
/// - ``canonical``
public struct FHIRCanonicalURL: Hashable, Sendable {
    /// The spelling this project writes.
    public let canonical: String

    /// Creates a canonical URL.
    public init(_ canonical: String) {
        self.canonical = canonical
    }
}


extension FHIRCanonicalURL: CustomStringConvertible {
    public var description: String {
        canonical
    }
}

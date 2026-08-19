//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// A FHIR canonical URL, together with every spelling it has previously been published under.
///
/// A canonical URL is an identifier, not a location. Once published it appears in resources this
/// project does not own — questionnaires authored elsewhere, observations already uploaded to a
/// research database — so it can never stop being understood, even when the authority behind it
/// changes.
///
/// Making the identifier a value that knows its own history, rather than a bare string, means reads
/// and writes both go through one place. Retiring a spelling is then a one-line edit at the
/// declaration instead of a change at every call site:
///
/// ```swift
/// static let sourceDevice = FHIRCanonicalURL(
///     "https://grovealliance.org/fhir/core/StructureDefinition/sourceDevice",
///     superseding: SupersededFHIRURLs.sourceDevice
/// )
/// ```
///
/// Deliberately backed by `String` rather than `URL`: the questionnaire read sites compile at the
/// package's lowest deployment target, below the availability of the `URL`-typed helpers.
///
/// ## Topics
///
/// ### Creating an Identifier
/// - ``init(_:superseding:)``
///
/// ### Spellings
/// - ``canonical``
/// - ``superseded``
/// - ``allSpellings``
public struct FHIRCanonicalURL: Hashable, Sendable {
    /// The spelling this project writes.
    public let canonical: String

    /// Spellings previously published, newest first. Read, never written.
    public let superseded: [String]

    /// Every spelling a resource might carry, canonical first.
    public var allSpellings: [String] {
        [canonical] + superseded
    }

    /// Creates a canonical URL.
    ///
    /// - Parameters:
    ///   - canonical: The spelling to write.
    ///   - superseding: Spellings previously published for the same concept, newest first.
    public init(_ canonical: String, superseding: [String] = []) {
        self.canonical = canonical
        self.superseded = superseding
        FHIRSupersessionRegistry.register(self)
    }
}


extension FHIRCanonicalURL: CustomStringConvertible {
    public var description: String {
        canonical
    }
}

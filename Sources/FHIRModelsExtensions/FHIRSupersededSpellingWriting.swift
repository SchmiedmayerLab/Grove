//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


/// Whether resources also carry the spellings this project has retired.
///
/// Writes emit the canonical spelling only. An analysis pipeline keyed on the pre-Grove URLs can opt
/// into a compatibility copy alongside it, which buys time to migrate the pipeline instead of forcing
/// it to happen on the same day as the app update.
///
/// ```swift
/// FHIRWritePolicy.default = .canonicalAndSuperseded
/// ```
///
/// - Important: Dual-written extensions are duplicates, not new information. Anything reading through
///     ``FHIRTypeWithExtensions/extensions(for:)-(FHIRCanonicalURL)`` already resolves both spellings
///     and should leave this alone.
public enum FHIRWritePolicy: Sendable, Hashable, CaseIterable {
    /// Emit only the current canonical spelling.
    case canonicalOnly
    /// Emit the canonical spelling, plus a copy under every spelling it superseded.
    case canonicalAndSuperseded

    /// The policy applied when a caller does not pass one explicitly.
    public static var `default`: Self {
        get { lock.withLock { storedDefault } }
        set { lock.withLock { storedDefault = newValue } }
    }

    nonisolated(unsafe) private static var storedDefault: Self = .canonicalOnly
    private static let lock = NSLock()
}


extension FHIRTypeWithExtensions {
    /// Adds a copy of every top-level extension belonging to one of `identifiers` under each spelling
    /// that identifier has superseded.
    ///
    /// Copies are deep, so a nested tree such as `sourceRevision/source/bundleIdentifier` is reproduced
    /// in full with every url rewritten — byte-for-byte what this project wrote before the rename.
    /// Existing superseded-spelled copies are removed first, which makes the pass idempotent.
    ///
    /// Does nothing under ``FHIRWritePolicy/canonicalOnly``.
    public mutating func writeSupersededSpellings(
        of identifiers: some Sequence<FHIRCanonicalURL>,
        policy: FHIRWritePolicy = .default
    ) {
        guard policy == .canonicalAndSuperseded, var elements = `extension` else {
            return
        }
        var additions: [Extension] = []
        for identifier in identifiers where !identifier.superseded.isEmpty {
            // Only rebuild when a canonical element exists to rebuild FROM. A resource written
            // before the rename carries the superseded spelling alone; removing it here would
            // destroy the resource's only copy of that extension.
            guard elements.contains(where: { $0.urlString == identifier.canonical }) else {
                continue
            }
            // Rebuild rather than append, so running twice cannot stack duplicates.
            elements.removeAll { identifier.superseded.contains($0.urlString ?? "") }
            for element in elements where element.urlString == identifier.canonical {
                additions += identifier.superseded.map {
                    element.rewritingURLPrefix(identifier.canonical, to: $0)
                }
            }
        }
        guard !additions.isEmpty else {
            `extension` = elements.isEmpty ? nil : elements
            return
        }
        `extension` = elements + additions
    }
}


extension ModelsR4.Extension {
    /// The extension's url as a plain string, if it has one.
    var urlString: String? {
        url.value?.url.absoluteString
    }

    /// Matching a top-level extension is exact; only the rewrite inside a copy is by prefix, where the
    /// spellings are prefix-parallel by construction because they are built by appending components.
    func rewritingURLPrefix(_ old: String, to new: String) -> Self {
        var copy = self
        if let spelling = urlString, spelling.hasPrefix(old), let rewritten = URL(string: new + spelling.dropFirst(old.count)) {
            copy.url = rewritten.asFHIRURIPrimitive()
        }
        copy.extension = `extension`?.map { $0.rewritingURLPrefix(old, to: new) }
        return copy
    }
}

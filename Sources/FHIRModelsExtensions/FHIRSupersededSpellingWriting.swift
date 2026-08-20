//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveLegacyIdentifiers
public import ModelsR4


/// Controls extension appending
public enum AppendExtensionBehaviour {
    /// Adding an extension does not affect existing extensions with the same URL, instead the new value simply gets appended.
    case additive
    /// Adding an extension causes all other existing extensions with the same URL to be removed.
    case replace
}


/// Whether resources also carry the spellings this project has retired.
///
/// Writes emit the canonical spelling only. An analysis pipeline keyed on the pre-Grove URLs can opt
/// into a compatibility copy alongside it, which buys time to migrate the pipeline instead of forcing
/// it to happen on the same day as the app update. The copy is the current payload under the old
/// name, so an identifier whose payload changed shape when its url did is left out entirely — see
/// `notReproducibleByDualWrite`.
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
    /// in full with every url rewritten. What it reproduces is the payload as written today, not the
    /// bytes of the release that retired the spelling: a rename the encoding survived unchanged gives
    /// the old pipeline exactly what it read before, while a spelling whose payload changed shape at
    /// the same time is skipped altogether (`notReproducibleByDualWrite`), since
    /// a copy in the current shape under the old name is not something any consumer has parsed.
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
        for identifier in identifiers {
            let spellings = identifier.superseded.filter {
                !SupersededFHIRURLs.notReproducibleByDualWrite.contains($0)
            }
            // Only rebuild when a canonical element exists to rebuild FROM. A resource written
            // before the rename carries the superseded spelling alone; removing it here would
            // destroy the resource's only copy of that extension.
            guard !spellings.isEmpty, elements.contains(where: { $0.urlString == identifier.canonical }) else {
                continue
            }
            // Rebuild rather than append, so running twice cannot stack duplicates.
            elements.removeAll { spellings.contains($0.urlString ?? "") }
            for element in elements where element.urlString == identifier.canonical {
                additions += spellings.map {
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


// Appending lives here rather than in the generated `FHIR+ExtensionUtils.swift`: it consults the
// supersession registry, and the next `./useGYB` run would drop a hook the template does not carry.
extension FHIRTypeWithExtensions {
    /// Appends an `Extension`
    ///
    /// - parameter extension: The extension to add
    /// - parameter behaviour: How the extension should be added, with respect to already-existing extensions with the same url.
    public mutating func append(extension: Extension, behaviour: AppendExtensionBehaviour = .additive) {
        append(extensions: CollectionOfOne(`extension`), behaviour: behaviour)
    }

    /// Appends multiple `Extension`s
    public mutating func append(extensions: some Collection<Extension>, behaviour: AppendExtensionBehaviour = .additive) {
        guard !extensions.isEmpty else {
            return
        }
        switch behaviour {
        case .additive:
            break
        case .replace:
            for element in extensions {
                removeAllExtensions(withUrl: element.url)
            }
        }
        var storage = `extension` ?? []
        storage.reserveCapacity(storage.count + extensions.count)
        storage.append(contentsOf: extensions)
        `extension` = storage
        // Nested extensions are mirrored with their complete tree when the enclosing resource
        // receives them. Mirroring here as well leaves retired children in the canonical tree and
        // duplicates those children when the top-level copy is created.
        guard !(self is ModelsR4.Extension) else {
            return
        }
        // Under .canonicalOnly this is a guard check; the appended urls are what a dual-write has to
        // mirror, so doing it here covers every writer instead of every writer remembering to.
        let retired = extensions.compactMap { element -> FHIRCanonicalURL? in
            guard let spelling = element.url.value?.url.absoluteString else {
                return nil
            }
            return FHIRSupersessionRegistry.identifier(forCanonical: spelling)
        }
        if !retired.isEmpty {
            writeSupersededSpellings(of: retired)
        }
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

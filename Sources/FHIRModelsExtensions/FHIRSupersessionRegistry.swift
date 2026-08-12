//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Every identifier that has retired spellings, recorded as those identifiers are created.
///
/// ``FHIRTypeWithExtensions/append(extensions:behaviour:)`` consults this so a dual-write reaches
/// every extension the project emits, rather than only the ones a call site remembered to name.
/// Registration happens in the initializer: an extension cannot be appended under an identifier whose
/// declaration has not been evaluated, so anything reaching `append` is already registered.
public enum FHIRSupersessionRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: [String: FHIRCanonicalURL] = [:]

    /// Every registered identifier that supersedes at least one earlier spelling.
    public static var all: [FHIRCanonicalURL] {
        lock.withLock { Array(storage.values) }
    }

    static func register(_ url: FHIRCanonicalURL) {
        guard !url.superseded.isEmpty else {
            return
        }
        lock.withLock { storage[url.canonical] = url }
    }

    /// The registered identifier for a canonical spelling, if it retired any.
    static func identifier(forCanonical canonical: String) -> FHIRCanonicalURL? {
        lock.withLock { storage[canonical] }
    }
}

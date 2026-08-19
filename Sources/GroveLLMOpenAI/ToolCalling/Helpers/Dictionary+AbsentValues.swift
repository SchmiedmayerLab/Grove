//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Dictionary where Key == String, Value == (any Sendable)? {
    /// Whether the existential wraps an optional that holds nothing.
    private static func isAbsent(_ value: any Sendable) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    /// The entries that actually carry a value, with the absent ones dropped.
    ///
    /// Compacting on the optional alone is not enough here. The schema literals cast each optional to
    /// `(any Sendable)?` to give the dictionary one value type, and casting an absent value that way wraps the `nil`
    /// inside a *non-nil* existential — so the compaction keeps it and it encodes as an explicit JSON `null`. A tool
    /// schema carrying `"enum": null` is rejected outright ("None is not of type 'array'"), so the difference
    /// between an absent key and a null one decides whether function calling works at all.
    func compactingAbsentValues() -> [String: any Sendable] {
        var result: [String: any Sendable] = [:]
        result.reserveCapacity(count)
        for (key, value) in self {
            guard let value, !Self.isAbsent(value) else {
                continue
            }
            result[key] = value
        }
        return result
    }
}

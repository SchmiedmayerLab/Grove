//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import Testing


private func expectEqual<Key: Hashable, Value: Equatable>(
    _ lhs: KeyValuePairs<Key, Value>,
    _ rhs: KeyValuePairs<Key, Value>,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let duplicateEntriesError = NSError(domain: "org.grovealliance", code: 0, userInfo: [
        NSLocalizedDescriptionKey: "Duplicate keys!"
    ])
    let lhs = try Dictionary(lhs.lazy.map { ($0, $1) }, uniquingKeysWith: { _, _ in throw duplicateEntriesError })
    let rhs = try Dictionary(rhs.lazy.map { ($0, $1) }, uniquingKeysWith: { _, _ in throw duplicateEntriesError })
    if lhs != rhs {
        Issue.record("'\(lhs)' was not equal to '\(rhs)'", sourceLocation: sourceLocation)
    }
}


@Suite
struct KeyValuePairsTests {
    @Test
    func createFromSequence() throws {
        let sequence: some Sequence<(String, Int)> = [
            ("A", 1), ("B", 2), ("C", 3), ("D", 4), ("E", 5), ("F", 6)
        ]
        try expectEqual(
            KeyValuePairs(sequence),
            ["A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6]
        )
    }
    
    @Test
    func createFromDictionary() throws {
        let dictionary = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6
        ]
        try expectEqual(
            KeyValuePairs(dictionary.lazy.map { ($0, $1) }),
            ["A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6]
        )
    }
}

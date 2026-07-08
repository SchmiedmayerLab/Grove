//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation
import Testing


@Suite
struct SequenceExtensions {
    @Test
    func mapIntoSet() {
        #expect([0, 1, 2, 3, 4].mapIntoSet { $0 * 2 } == [0, 2, 4, 6, 8])
        #expect([0, 1, 2, 3, 4].mapIntoSet { $0 / 2 } == [0, 1, 2])
    }
    
    @Test
    func compactMapIntoSet() {
        #expect([0, 1, 2, 3, 4].compactMapIntoSet { $0.isMultiple(of: 2) ? $0 * 2 : nil } == [0, 4, 8])
        #expect([0, 1, 2, 3, 4].compactMapIntoSet { $0.isMultiple(of: 2) ? $0 / 2 : nil } == [0, 1, 2])
    }
    
    @Test
    func flatMapIntoSet() {
        struct Person {
            let name: String
            let petNames: [String]
        }
        let lukas = Person(name: "Lukas", petNames: ["Snugglebug", "Tofu", "Clover", "Muffin"])
        let paul = Person(name: "Paul", petNames: ["Pudding", "Sprout", "Clover"])
        #expect([paul, lukas].flatMapIntoSet(\.petNames) == ["Snugglebug", "Tofu", "Clover", "Pudding", "Muffin", "Sprout"])
    }
    
    @Test
    func removeAtIndices() {
        var array = Array(0...9)
        array.remove(at: [0, 7, 5, 2])
        #expect(array == [1, 3, 4, 6, 8, 9])
        
        array = Array(0...9)
        array.remove(at: [0, 7, 5, 2] as IndexSet)
        #expect(array == [1, 3, 4, 6, 8, 9])
    }
    
    
    @Test
    func search() {
        let numbers = Array(0...20)
        #expect(numbers.binarySearchForIndex(of: 5, using: Int.compare) == .found(5))
        #expect(numbers.binarySearchForIndex(of: 21, using: Int.compare) == .notFound(numbers.endIndex))
        #expect(numbers.binarySearchForIndex(of: -1, using: Int.compare) == .notFound(numbers.startIndex))
        #expect(numbers.binarySearchFirstIndex(where: { other in
            if 7 < other { // swiftlint:disable:this yoda_condition
                .orderedAscending
            } else if 7 == other { // swiftlint:disable:this yoda_condition
                .orderedSame
            } else {
                .orderedDescending
            }
        }) == .found(7))
    }
    
    
    @Test
    func indexing() {
        let input = [0, 1, 2]
        #expect(input[safe: 0] == 0)
        #expect(input[safe: 1] == 1)
        #expect(input[safe: 2] == 2)
        #expect(input[safe: 3] == nil)
        #expect(input[unsafe: 0] == 0)
        #expect(input[unsafe: 1] == 1)
        #expect(input[unsafe: 2] == 2)
    }
    
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func multiComparatorSorting() {
        struct Cat: Equatable {
            let name: String
            let age: Int
        }
        var cats = [
            Cat(name: "Terrace", age: 7),
            Cat(name: "Pixel", age: 5),
            Cat(name: "Pixel", age: 4)
        ]
        cats.sort(using: [
            KeyPathComparator<Cat>(\.name),
            KeyPathComparator<Cat>(\.age)
        ] as [any SortComparator<Cat>])
        #expect(cats == [
            Cat(name: "Pixel", age: 4),
            Cat(name: "Pixel", age: 5),
            Cat(name: "Terrace", age: 7)
        ])
    }
}


extension Comparable {
    static func compare(_ lhs: Self, _ rhs: Self) -> ComparisonResult {
        if lhs < rhs {
            ComparisonResult.orderedAscending
        } else if rhs < lhs {
            ComparisonResult.orderedDescending
        } else {
            ComparisonResult.orderedSame
        }
    }
}

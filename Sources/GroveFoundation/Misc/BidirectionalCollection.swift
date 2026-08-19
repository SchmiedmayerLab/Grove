//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


extension BidirectionalCollection {
    /// Determines whether the collection ends with the elements of another collection.
    @inlinable
    public func ends(
        with possibleSuffix: some BidirectionalCollection<Element>
    ) -> Bool where Element: Equatable {
        ends(with: possibleSuffix, by: ==)
    }
    
    
    /// Determines whether the collection ends with the elements of another collection.
    public func ends<PossibleSuffix: BidirectionalCollection, E: Error>(
        with possibleSuffix: PossibleSuffix,
        by areEquivalent: (Element, PossibleSuffix.Element) throws(E) -> Bool
    ) throws(E) -> Bool {
        guard self.count >= possibleSuffix.count else {
            return false
        }
        for (elem1, elem2) in zip(self.reversed(), possibleSuffix.reversed()) {
            guard try areEquivalent(elem1, elem2) else {
                return false
            }
        }
        return true
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


// SAFETY: We're declaring a retroactive conformance here, i.e. we are extending a type we don't own by making it conform to a protocol we don't own.
// This is fine, in this specific case, since `StaticString` is a frozen type, meaning that we can safely assume that its layout and public properties
// won't change. Furthermore, in this specific case there really is only one sensible way of implementing this.
// Should this ever get added to the Standard Library, we should remove this conformance.
extension StaticString: @retroactive Hashable {
    /// Compares two `StaticString` instances for equality.
    ///
    /// This function returns `true` iff `lhs` and `rhs` have the same contents, otherwise `false`.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.hasPointerRepresentation, rhs.hasPointerRepresentation) {
        case (true, true):
            // the two strings are either truly identical (if they point to the same address),
            // or they point to different memory locations which then contain identical contents
            lhs.utf8Start == rhs.utf8Start || strcmp(lhs.utf8Start, rhs.utf8Start) == 0
        case (false, false):
            lhs.unicodeScalar == rhs.unicodeScalar
        case (true, false), (false, true):
            false
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        if self.hasPointerRepresentation {
            hasher.combine(self.utf8Start)
        } else {
            hasher.combine(self.unicodeScalar)
        }
    }
}

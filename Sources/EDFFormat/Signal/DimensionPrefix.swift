//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Dimension prefixes for SI units.
///
/// For more information refer to [EDF+ Dimension Prefixes](https://www.edfplus.info/specs/edftexts.html#prefixes_electrodenames).
public enum DimensionPrefix: String {
    /// Decimal power of 24
    case yotta = "Y"
    /// Decimal power of 21
    case zetta = "Z"
    /// Decimal power of 18
    case exa = "E"
    /// Decimal power of 15
    case peta = "P"
    /// Decimal power of 12
    case tera = "T"
    /// Decimal power of 9
    case giga = "G"
    /// Decimal power of 6
    case mega = "M"
    /// Decimal power of 3
    case kilo = "K"
    /// Decimal power of 2
    case hecto = "H"
    /// Decimal power of 1
    case deca = "D"
    /// No decimal power (0)
    case none = ""
    /// Decimal power of -1
    case deci = "d"
    /// Decimal power of -2
    case centi = "c"
    /// Decimal power of -3
    case milli = "m"
    /// Decimal power of -6
    case micro = "u"
    /// Decimal power of -9
    case nano = "n"
    /// Decimal power of -12
    case pico = "p"
    /// Decimal power of -15
    case femto = "f"
    /// Decimal power of -18
    case atto = "a"
    /// Decimal power of -21
    case zepto = "z"
    /// Decimal power of -24
    case yocto = "y"
}


extension DimensionPrefix: Hashable, Sendable {}

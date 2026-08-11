//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A matching descriptor for a `Data`-based field.
///
/// To match against `Data`, you provide the ``data`` you want to match to, with an additional ``mask`` that defines which bits should be considered for the check.
public struct DataDescriptor {
    /// The data to match against.
    public let data: Data
    /// The mask that
    public let mask: Data

    /// Create a new data descriptor.
    /// - Parameters:
    ///   - data: The data.
    ///   - mask: The mask.
    public init(data: Data, mask: Data) {
        self.data = data
        self.mask = mask
        precondition(mask.count == data.count, "The data mask must the data size. Mask length \(mask.count), data length \(data.count).")
    }

    /// Create a new data descriptor with a mask that matches all bits.
    /// - Parameter data: The data.
    public init(data: Data) {
        let mask = Data(repeating: 0xFF, count: data.count)
        self.init(data: data, mask: mask)
    }

    private static func bitwiseAnd(lhs: Data, rhs: Data) -> [UInt8] {
        if rhs.count > lhs.count {
            return bitwiseAnd(lhs: rhs, rhs: lhs)
        }

        var value: [UInt8] = Array(repeating: 0, count: max(rhs.count, lhs.count))
        var index = 0

        for (lhsIndex, rhsIndex) in zip(lhs.indices, rhs.indices) {
            value[index] = lhs[lhsIndex] & rhs[rhsIndex]
            index += 1
        }

        return value
    }

    /// Determine if the data descriptor matches the provided Data value.
    /// - Parameter value: The data value to check if it matches the descriptor.
    /// - Returns: Return `true` if the bits as defined by ``mask`` if `value` and ``data`` are equal.
    public func matches(_ value: Data) -> Bool {
        let valueMasked = Self.bitwiseAnd(lhs: value, rhs: mask)
        let dataMasked = Self.bitwiseAnd(lhs: data, rhs: mask)

        return Self.equalBitPattern(lhs: valueMasked, rhs: dataMasked)
    }
}


extension DataDescriptor: Sendable, Hashable {
    /// Determine if two data blobs expose the same bit pattern (e.g., additional zero bytes do not matter)
    /// - Parameters:
    ///   - lhs: The left-hand-side.
    ///   - rhs: The right-hand-side.
    /// - Returns: Returns `true` if the bit pattern matches.
    static func equalBitPattern<D: Collection<UInt8>>(lhs: D, rhs: D) -> Bool {
        if rhs.count > lhs.count {
            return Self.equalBitPattern(lhs: rhs, rhs: lhs)
        }

        if lhs.count > rhs.count {
            guard lhs[rhs.endIndex...].allSatisfy({ $0 == 0 }) else {
                return false
            }
        }

        for index in rhs.indices {
            guard lhs[index] == rhs[index] else {
                return false
            }
        }

        return true
    }

    public static func == (lhs: DataDescriptor, rhs: DataDescriptor) -> Bool {
        Self.equalBitPattern(lhs: lhs.mask, rhs: rhs.mask)
        && Self.equalBitPattern(
            lhs: Self.bitwiseAnd(lhs: lhs.data, rhs: lhs.mask),
            rhs: Self.bitwiseAnd(lhs: rhs.data, rhs: rhs.mask)
        )
    }
}


extension DataDescriptor: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        """
        DataDescriptor(\
        data: \(data.map { String(format: "%02hhx", $0) }.joined()), \
        mask: \(mask.map { String(format: "%02hhx", $0) }.joined())
        """
    }

    public var debugDescription: String {
        description
    }
}

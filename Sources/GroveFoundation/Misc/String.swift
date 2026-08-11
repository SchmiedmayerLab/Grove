//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Algorithms

extension StringProtocol {
    /// Removes all leading and trailing whitespace (including newlines) from the string.
    @inlinable
    public func trimmingWhitespace() -> SubSequence {
        trimming(while: \.isWhitespace)
    }
    
    /// Removes all leading and trailing whitespace (including newlines) from the string.
    @inlinable
    @_disfavoredOverload
    public func trimmingWhitespace() -> String {
        String(trimmingWhitespace())
    }
}

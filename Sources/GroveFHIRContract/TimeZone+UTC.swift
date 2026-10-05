//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


extension TimeZone {
    /// Coordinated Universal Time, in which the converter states its own clock instants.
    package static let utc: TimeZone = {
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("Foundation must provide a zero-offset time zone.")
        }
        return utc
    }()
}

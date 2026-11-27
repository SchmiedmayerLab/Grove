//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension Decimal {
    /// The `Double` nearest to the decimal.
    ///
    /// `NSDecimalNumber.doubleValue` is not correctly rounded: it turns `36.52` into
    /// `36.519999999999996`, which then differs from the `36.52` a participant types.
    var doubleValue: Double {
        Double(description) ?? NSDecimalNumber(decimal: self).doubleValue
    }
}

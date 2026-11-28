//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveQuestionnaire
import ModelsR4


extension Decimal {
    /// The `Double` nearest to the decimal.
    ///
    /// `NSDecimalNumber.doubleValue` is not correctly rounded: it turns `36.52` into
    /// `36.519999999999996`, which then differs from the `36.52` a participant types.
    var doubleValue: Double {
        Double(description) ?? NSDecimalNumber(decimal: self).doubleValue
    }
}


extension Double {
    /// The FHIR decimal with the shortest digits that convert back to the value.
    ///
    /// `asFHIRDecimalPrimitive()` expands the binary value, so a typed `36.52` would be exported as
    /// `36.52000000000000512` and no longer equal an `answerDecimal` of `36.52`.
    var shortestFHIRDecimal: FHIRPrimitive<FHIRDecimal> {
        FHIRPrimitive(FHIRDecimal(Decimal(shortestDigitsOf: self) ?? Decimal(self)))
    }
}

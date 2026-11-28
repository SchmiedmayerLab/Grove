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


@available(iOS 18, macOS 15, watchOS 11, *)
extension Quantity {
    /// A `Quantity` of `value` in `unit`.
    init(_ unit: RecordedQuantityUnit, value: FHIRPrimitive<FHIRDecimal>) {
        self.init(
            code: unit.code?.asFHIRStringPrimitive(),
            system: unit.system?.asFHIRURIPrimitive(),
            unit: unit.text?.asFHIRStringPrimitive(),
            value: value
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRTime {
    /// The whole seconds of the time.
    var wholeSeconds: Int {
        var seconds = second
        var whole = Decimal()
        NSDecimalRound(&whole, &seconds, 0, .down)
        return NSDecimalNumber(decimal: whole).intValue
    }

    /// The fraction of a second in nanoseconds, finer digits dropped; `nil` for a whole second.
    var nanoseconds: Int? {
        var fraction = (second - Decimal(wholeSeconds)) * 1_000_000_000
        var nanoseconds = Decimal()
        NSDecimalRound(&nanoseconds, &fraction, 0, .down)
        let value = NSDecimalNumber(decimal: nanoseconds).intValue
        return value == 0 ? nil : value
    }

    /// The time of day of `components`, with its fraction of a second.
    init(timeOf components: DateComponents) {
        self.init(
            hour: UInt8(clamping: components.hour ?? 0),
            minute: UInt8(clamping: components.minute ?? 0),
            second: Decimal(components.second ?? 0) + Decimal(components.nanosecond ?? 0) / 1_000_000_000
        )
    }
}

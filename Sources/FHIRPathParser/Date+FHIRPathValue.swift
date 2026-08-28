//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension Date: _FHIRPathValue {
    public static func evaluate(
        _ expression: FHIRPathParser.ExpressionContext,
        evaluationInstant: Date
    ) throws -> Date {
        switch expression.accept(DateExpressionEvaluation(evaluationInstant: evaluationInstant)) {
        case .none:
            throw DateExpressionError.internalError
        case let .failure(error):
            throw error
        case let .success(value):
            switch value {
            case let .components(components):
                // if the date components represent a valid date, we try the conversion
                let calendar = FHIRPathCalendar.gregorian(
                    timeZone: components.timeZone ?? FHIRPathCalendar.utc
                )
                guard components.year != nil, let date = calendar.date(from: components) else {
                    throw DateExpressionError.failedDateOperation(reason: .componentsDoNotFormValidDate)
                }
                return date
            case let .date(date):
                return date
            }
        }
    }
}


extension DateComponents: _FHIRPathValue {
    public static func evaluate(
        _ expression: FHIRPathParser.ExpressionContext,
        evaluationInstant: Date
    ) throws -> DateComponents {
        switch expression.accept(DateExpressionEvaluation(evaluationInstant: evaluationInstant)) {
        case .none:
            throw DateExpressionError.internalError
        case let .failure(error):
            throw error
        case let .success(value):
            switch value {
            case let .components(components):
                return components
            case let .date(date):
                return FHIRPathCalendar.gregorian().dateComponents(
                    [.timeZone, .year, .month, .day, .hour, .minute, .second],
                    from: date
                )
            }
        }
    }
}

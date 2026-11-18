//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFHIRContract


/// Valid typed rows for transport/escaping tests; malformed-value tests state their bytes separately.
enum RecordingCSVSchemaFixtures {
    static func row(format: RegisteredRecordingFormat, variant: Int) -> [RecordingCSVWriter.Field] {
        (format.csvSchema ?? []).map { column in
            if column.nullable && variant.isMultiple(of: 2) {
                return .absent
            }
            return switch column.type {
            case .string: .text("é,\"quoted\"\nline \(variant)")
            case .integer: .integer(variant)
            case .number: .number(Double(variant) + 0.125)
            case .timestamp: .timestamp(Date(timeIntervalSince1970: 1_800_000_000.125 + Double(variant)))
            }
        }
    }
}

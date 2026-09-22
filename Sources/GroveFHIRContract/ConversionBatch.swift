//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Explicit successes and failures from a batch conversion; no record is dropped silently.
public struct ConversionBatch<Conversion: Sendable, Failure: Sendable>: Sendable {
    public let conversions: [Conversion]
    public let failures: [Failure]

    public init(conversions: [Conversion], failures: [Failure]) {
        self.conversions = conversions
        self.failures = failures
    }
}

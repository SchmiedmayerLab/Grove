//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(HealthKit)

public import Foundation


/// Failure for one record in a batch. The original source identity and typed reason are
/// retained; batch conversion never drops a record silently.
public struct HealthKitRecordFailure: Error, Equatable, Sendable {
    public let sourceUUID: UUID
    public let sourceTypeIdentifier: String
    public let reason: HealthKitConversionError
}


/// Explicit successes and failures from a batch conversion.
public struct HealthKitBatchResult: Sendable {
    public let conversions: [HealthKitConversion]
    public let failures: [HealthKitRecordFailure]
}

#endif

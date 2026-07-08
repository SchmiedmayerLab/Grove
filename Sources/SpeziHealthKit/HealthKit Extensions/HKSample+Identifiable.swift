//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import HealthKit


@available(macOS 13.0, *)
extension HKSample: @retroactive Identifiable {
    /// The `uuid` identifier.
    public var id: UUID {
        uuid
    }
}


@available(macOS 13.0, *)
extension HKSample {
    /// The sample's time range.
    public var timeRange: Range<Date> {
        startDate..<endDate
    }
}

#endif

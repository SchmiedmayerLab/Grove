//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit


/// The assembly's entry points under one explicit conversion context, as the tests state their inputs: each builds
/// what the exporter builds for the same record under that context's event.
extension HealthKitAssembly {
    /// One sample's conversion.
    static func convert(_ sample: HKSample, context: HealthKitConversionContext) throws -> HealthKitConversionSet {
        try HealthKitAssembly(context: context.event).convert(sample, request: .init(context: context))
    }

    /// A heartbeat series' recording document.
    static func convert(_ record: HealthKitHeartbeatSeriesRecord, context: HealthKitConversionContext) throws -> HealthKitConversionSet {
        try HealthKitAssembly(context: context.event).convertHeartbeatSeries(record, request: .init(context: context))
    }

    /// A workout route's recording document, or `nil` when the context does not authorize disclosing the route.
    static func convert(_ record: HealthKitWorkoutRouteRecord, context: HealthKitConversionContext) throws -> HealthKitConversionSet? {
        try HealthKitAssembly(context: context.event).convertWorkoutRoute(record, request: .init(context: context))
    }

    /// A deleted record's retraction.
    static func retraction(
        of record: HealthKitSourceRecord,
        context: HealthKitConversionContext,
        occurred: RetractionOccurrence
    ) throws -> RetractionEvent {
        try HealthKitAssembly(context: context.event).retraction(of: record, request: .init(context: context), occurred: occurred)
    }
}

#endif

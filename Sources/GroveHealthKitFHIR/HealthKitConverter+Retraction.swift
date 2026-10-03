//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
public import GroveFHIRContract
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The complete retraction of a deleted record, as its own exchange event.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter.retract; removed with the exporter rework's final cleanup.")
    public func retraction(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext,
        occurred: RetractionOccurrence
    ) throws(HealthKitConversionError) -> RetractionEvent {
        try Self.validate(context: context)
        return try HealthKitAssembly(context: context.event).retraction(of: record, request: .init(context: context), occurred: occurred)
    }

    /// The logical targets a deletion retracts, named from the catalog alone.
    @available(*, deprecated, message: "Use HealthKitFHIRExporter.retract; removed with the exporter rework's final cleanup.")
    public func retractionTargets(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> [RetractionTarget] {
        try Self.validate(context: context)
        return try HealthKitAssembly(context: context.event).retractionTargets(of: record, request: .init(context: context))
    }
}


extension HealthKitSourceType {
    /// The inventory row of a sample type, such as the one a deletion was reported for.
    public init?(_ sampleType: HKSampleType) {
        self.init(rawValue: sampleType.identifier)
    }
}


extension HealthKitConversionError {
    init(_ error: RetractionEventError) {
        self = switch error {
        case .reservedIdentifierSystem: .reservedIdentifierSystem
        case .opaqueIdentity(let error): .opaqueIdentity(error)
        case .exchangeIdentity(let error): .exchangeIdentity(error)
        case .exchangeGraph(let error): .exchangeGraph(error)
        case .emptyTargets, .duplicateTarget, .invalidSourceRecord, .invalidInstant, .invalidOccurrencePeriod:
            .dependency(HealthKitDependencyFailure(underlying: error))
        }
    }
}

#endif

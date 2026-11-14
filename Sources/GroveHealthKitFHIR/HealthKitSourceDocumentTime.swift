//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    static func sourceDocumentTime(_ sample: HKSample, metadata: HealthKitSampleMetadata) throws -> Extension? {
        #if os(watchOS)
        return nil
        #else
        let basis: HealthKitSourceDocumentTime.Basis
        switch sample {
        case is HKClinicalRecord: basis = .clinicalRecordDownload
        case is HKCDADocumentSample: basis = .cdaSourceDocumentPeriod
        default: return nil
        }
        guard try EffectiveRule.interval(nonZero: false).admitsPeriod(from: sample.startDate, to: sample.endDate) else {
            throw HealthKitConversionError.ValueFailure.effectivePeriodInvalid
        }
        let period = try HealthKitEffectiveTime.period(start: sample.startDate, end: sample.endDate, zone: metadata.timeZone())
        return HealthKitSourceDocumentTime.make(basis: basis, period: period)
        #endif
    }

    /// Source-document time accounts for its source timezone without a duplicate metadata representation.
    func sourceEvidence(
        _ sample: HKSample, metadata: HealthKitSampleMetadata
    ) throws -> (extensions: [Extension], metadataKeys: Set<String>) {
        var values = sourceRevision.map { [$0] } ?? []
        let sourceTime = try Self.sourceDocumentTime(sample, metadata: metadata)
        if let sourceTime { values.append(sourceTime) }
        return (values, sourceTime == nil ? [] : [HKMetadataKeyTimeZone])
    }
}

#endif

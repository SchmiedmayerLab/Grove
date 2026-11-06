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


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter {
    /// What the writer and unit-token policies answer for one sample, resolved once per input that names it.
    struct ResolvedPolicies: Sendable {
        /// The answers for no sample: no writer and no unit. A retraction states neither.
        static let unresolved = ResolvedPolicies(writer: .omit, unitToken: nil)

        let writer: HealthKitFHIRExporter.WriterPolicy.Classification
        /// `nil` when the sample names no `HKDevice` or the policy picks no token for it.
        let unitToken: String?
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.ResolvedPolicies {
    /// What `options`' writer and unit-token policies answer for `sample`.
    init(_ sample: HKSample, options: HealthKitFHIRExporter.Options) {
        let source = sample.sourceRevision.source
        self.init(
            writer: options.writer.classification(of: source),
            unitToken: sample.device.flatMap { options.unitToken.token(for: $0, source: source) }
        )
    }
}

#endif

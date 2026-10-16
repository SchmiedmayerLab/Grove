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
    /// What the writer and recording-device policies answer for one sample, resolved once per input that names it,
    /// before its event is reserved: the event's fingerprint covers these answers and its graph states them, so a
    /// ``WriterPolicy/classify(_:)`` closure or a custom ``RecordingDevicePolicy`` resolver that answers otherwise
    /// for a reserved record takes a new sequence instead of restating the reserved event.
    struct ResolvedPolicies: ExchangeContextFingerprinted, Sendable {
        /// The answers for no sample: no writer and no recording Device. A retraction states neither.
        static let unresolved = ResolvedPolicies(writer: .omit, recordingDevice: nil)

        let writer: HealthKitFHIRExporter.WriterPolicy.Classification
        /// `nil` when the sample names no `HKDevice` or the policy declines it.
        let recordingDevice: RecordingDevice?

        /// The writer tag, then the recording device's: `none`, or `unit` and every value of the device the graph
        /// states, its token (which keys the Device's identities) and its optional name, manufacturer and model.
        var fingerprintParts: [String] {
            let device = recordingDevice.map { device in
                ["unit", device.stableUnitToken]
                    + Self.optionalParts(device.name) + Self.optionalParts(device.manufacturer) + Self.optionalParts(device.modelNumber)
            }
            return ["writer"] + writer.fingerprintParts + ["recordingDevice"] + (device ?? ["none"])
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitFHIRExporter.ResolvedPolicies {
    /// What `options`' writer and recording-device policies answer for `sample`.
    init(_ sample: HKSample, options: HealthKitFHIRExporter.Options) {
        self.init(
            writer: options.writer.classification(of: sample.sourceRevision.source),
            recordingDevice: sample.device.flatMap(options.recordingDevice.recordingDevice(for:))
        )
    }
}

#endif

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SensorKit
import SpeziFoundation


/// An ECG Session recorded by SensorKit.
@available(iOS 17.4, *)
public struct SensorKitECGSession: SensorKitSampleSafeRepresentation {
    /// A Batch of voltage samples that are associated with the same time offset.
    public struct Batch: Hashable, Sendable {
        /// A voltage sample.
        public struct VoltageSample: Hashable, Sendable {
            /// Sensor context associated with the voltage sample.
            public let flags: SRElectrocardiogramData.Flags
            /// Value of the ECG AC data in microvolts
            public let voltage: Measurement<UnitElectricPotentialDifference>
            
            init(_ data: SRElectrocardiogramData) {
                flags = data.flags
                voltage = data.value
            }
        }
        
        /// The batch's offset from the start of the ECG, in seconds.
        public let offset: TimeInterval
        /// The batch's voltage samples.
        public let samples: [VoltageSample]
    }
    
    
    /// Start date of the overall ECG.
    public let startDate: Date
    
    @inlinable public var timeRange: Range<Date> {
        startDate..<startDate.addingTimeInterval(duration)
    }
    
    /// The total duration of the ECG, in seconds.
    public let duration: TimeInterval
    
    /// Frequency in hertz at which the ECG data was recorded.
    public let frequency: Measurement<UnitFrequency>
    
    /// The lead that was used when recording the ECG data.
    public let lead: SRElectrocardiogramSample.Lead
    
    /// The type of session guidance used when recording the ECG data.
    public let guidance: SRElectrocardiogramSession.SessionGuidance
    
    /// The individual batches of data.
    public let batches: [Batch]
    
    fileprivate init(
        startDate: Date,
        frequency: Measurement<UnitFrequency>,
        lead: SRElectrocardiogramSample.Lead,
        guidance: SRElectrocardiogramSession.SessionGuidance,
        batches: [Batch]
    ) {
        assert(batches.isSorted { $0.offset < $1.offset })
        self.startDate = startDate
        self.duration = batches.last?.offset ?? 0
        self.frequency = frequency
        self.lead = lead
        self.guidance = guidance
        self.batches = batches
    }
}


// MARK: SensorKit ECG Session Processing

@available(iOS 17.4, *)
extension SRElectrocardiogramSample: SensorKitSampleProtocol {
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRElectrocardiogramSample)>
    ) -> [SensorKitECGSession] {
        let samplesBySession = Dictionary(grouping: samples.lazy.map(\.sample), by: \.session)
        guard !samplesBySession.isEmpty || samplesBySession.contains(where: { !$0.value.isEmpty }) else {
            return []
        }
        // NOTE: it seems that an `SRElectrocardiogramSession` object does not, as one might intuitively expect,
        // correspond to a single session for which the ECG sensor was active.
        // Instead, there will be multiple `SRElectrocardiogramSession` objects for a single logical session
        // (they will all have the same `identifier`), each representing a different state of the session.
        let sessionsByIdentifier = Dictionary(grouping: samplesBySession.keys, by: \.identifier)
        return sessionsByIdentifier.compactMap { _, sessions -> SensorKitECGSession? in
            guard let beginSession = sessions.first(where: { $0.state == .begin }),
                  let activeSession = sessions.first(where: { $0.state == .active }) else {
                return nil
            }
            assert(
                sessions.compactMapIntoSet { samplesBySession[$0]?.reduce(0) { $0 + $1.data.count } }.count { $0 > 0 } == 1
            ) // only one session should have samples?
            guard let samples = samplesBySession[activeSession]?.sorted(using: KeyPathComparator(\.date)), !samples.isEmpty else {
                return nil
            }
            assert(samples.mapIntoSet(\.lead).count == 1) // all samples should have same frequency?
            assert(samples.mapIntoSet(\.frequency).count == 1) // all samples should have same frequency?
            assert(samples.mapIntoSet(\.date).count == samples.count)
            // swiftlint:disable:next force_unwrapping
            let startDate = samplesBySession[beginSession]?.min(of: \.date) ?? samples.first!.date // we just sorted samples by date.
            return SensorKitECGSession(
                startDate: startDate,
                frequency: samples.first!.frequency, // swiftlint:disable:this force_unwrapping
                lead: samples.first!.lead, // swiftlint:disable:this force_unwrapping
                guidance: activeSession.sessionGuidance,
                batches: samples.map { (sample: SRElectrocardiogramSample) -> SensorKitECGSession.Batch in
                    SensorKitECGSession.Batch(
                        offset: sample.date.timeIntervalSince(startDate),
                        samples: sample.data.map(SensorKitECGSession.Batch.VoltageSample.init)
                    )
                }
            )
        }
    }
}


extension Sequence {
    func min<T: Comparable>(of keyPath: KeyPath<Element, T>) -> T? {
        self.min { $0[keyPath: keyPath] < $1[keyPath: keyPath] }?[keyPath: keyPath]
    }
}

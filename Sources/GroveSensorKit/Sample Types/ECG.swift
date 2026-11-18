//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import GroveFoundation
public import SensorKit


/// An ECG Session recorded by SensorKit.
@available(iOS 17.4, *)
public struct SensorKitECGSession: SensorKitSampleSafeRepresentation {
    /// Why fetched ECG samples could not be assembled into sessions.
    ///
    /// None of these failures advances the acquisition cursor, so the batch remains available for a retry.
    public enum ProcessingError: Error, Equatable, Sendable {
        /// A session lacks its begin, active or end state, or its voltage samples.
        case incompleteSession
        /// A session states one state more than once, mixes frequencies, leads or guidance, or has no identifier.
        case inconsistentSession
        /// A session's start, frequency or sample dates are not finite, or two samples share a date.
        case invalidTiming
        /// The sessions exceed the ``SensorKitECGProcessingLimits``.
        case assemblyCapacityExceeded
    }

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

            init(
                flags: SRElectrocardiogramData.Flags,
                voltage: Measurement<UnitElectricPotentialDifference>
            ) {
                self.flags = flags
                self.voltage = voltage
            }
        }
        
        /// The batch's offset from the start of the ECG, in seconds.
        public let offset: TimeInterval
        /// The batch's voltage samples.
        public let samples: [VoltageSample]
    }
    
    
    /// Start date of the overall ECG.
    public let startDate: Date

    /// The SensorKit identifier that joins every provider session state for this ECG.
    public let sessionIdentifier: String

    /// The provider session states observed while assembling this ECG.
    ///
    /// Grove sorts these values by their raw representation so the safe representation remains
    /// deterministic even though SensorKit supplies distinct session objects for one logical ECG.
    public let sessionStates: [SRElectrocardiogramSession.State]
    
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
    
    init(
        startDate: Date,
        sessionIdentifier: String,
        sessionStates: [SRElectrocardiogramSession.State],
        frequency: Measurement<UnitFrequency>,
        lead: SRElectrocardiogramSample.Lead,
        guidance: SRElectrocardiogramSession.SessionGuidance,
        batches: [Batch]
    ) {
        assert(batches.isSorted { $0.offset < $1.offset })
        self.startDate = startDate
        self.sessionIdentifier = sessionIdentifier
        self.sessionStates = sessionStates.sorted { $0.rawValue < $1.rawValue }
        let frequencyHertz = frequency.converted(to: .hertz).value
        assert(frequencyHertz.isFinite && frequencyHertz > 0)
        if let finalBatch = batches.last,
           !finalBatch.samples.isEmpty,
           frequencyHertz.isFinite,
           frequencyHertz > 0 {
            self.duration = finalBatch.offset + Double(finalBatch.samples.count - 1) / frequencyHertz
        } else {
            self.duration = batches.last?.offset ?? 0
        }
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
    ) throws -> [SensorKitECGSession] {
        try SensorKitECGSession.process(inputGroups(samples))
    }

    static func inputGroups(
        _ samples: some Sequence<(timestamp: Date, sample: SRElectrocardiogramSample)>
    ) -> [SensorKitECGSession.InputGroup] {
        Dictionary(grouping: samples.lazy.map(\.sample), by: \.session).map { session, samples in
            SensorKitECGSession.InputGroup(
                identifier: session.identifier,
                state: session.state,
                guidance: session.sessionGuidance,
                readings: samples.map { sample in
                    SensorKitECGSession.InputReading(
                        date: sample.date,
                        frequency: sample.frequency,
                        lead: sample.lead,
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

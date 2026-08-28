//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
public import CoreMotion
import Foundation
public import GroveSensorKit
public import SensorKit


extension SensorKitRotationRateRecord {
    /// Creates a FHIR input from already-fetched Grove SensorKit values.
    ///
    /// This initializer performs no SensorKit query and gives the caller ownership of stable source identity.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        samples: [CMRecordedRotationRateData.SafeRepresentation]
    ) {
        self.init(
            sourceRecordID: sourceRecordID,
            samples: samples.map { sample in
                SensorKitRotationRateSample(
                    timestamp: sample.timestamp,
                    x: sample.rotationRate.x,
                    y: sample.rotationRate.y,
                    z: sample.rotationRate.z
                )
            }
        )
    }
}


@available(iOS 17.4, *)
extension SensorKitECGRecord {
    /// Creates a strict hybrid ECG input from an already-fetched Grove SensorKit session.
    ///
    /// `nativeRecording` must contain the exact corresponding native session evidence, including
    /// per-point SensorKit flags and session state. Grove neither fetches nor inspects those bytes.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        session: SensorKitECGSession,
        nativeRecording: SensorKitNativeRecording
    ) throws {
        let frequency = session.frequency.converted(to: .hertz).value
        guard frequency.isFinite, frequency > 0 else {
            throw SensorKitRecordError.invalidSamplingFrequency(frequency)
        }
        guard let finalBatch = session.batches.last, !finalBatch.samples.isEmpty else {
            throw SensorKitRecordError.emptySamples
        }
        let finalSampleOffset = finalBatch.offset + Double(finalBatch.samples.count - 1) / frequency
        self.init(
            sourceRecordID: sourceRecordID,
            startDate: session.startDate,
            durationSeconds: finalSampleOffset,
            frequencyHertz: frequency,
            lead: try Self.lead(session.lead),
            guidance: try Self.guidance(session.guidance),
            batches: session.batches.map { batch in
                SensorKitECGBatch(
                    offsetSeconds: batch.offset,
                    millivolts: batch.samples.map { sample in
                        sample.voltage.converted(to: .millivolts).value
                    }
                )
            },
            nativeRecording: nativeRecording
        )
    }

    private static func lead(_ value: SRElectrocardiogramSample.Lead) throws -> SensorKitECGLead {
        switch value {
        case .rightArmMinusLeftArm: .rightArmMinusLeftArm
        case .leftArmMinusRightArm: .leftArmMinusRightArm
        @unknown default:
            throw SensorKitRecordError.unsupportedProviderValue(
                field: "electrocardiogram.lead",
                rawValue: value.rawValue
            )
        }
    }

    private static func guidance(
        _ value: SRElectrocardiogramSession.SessionGuidance
    ) throws -> SensorKitECGGuidance {
        switch value {
        case .guided: .guided
        case .unguided: .unguided
        @unknown default:
            throw SensorKitRecordError.unsupportedProviderValue(
                field: "electrocardiogram.guidance",
                rawValue: value.rawValue
            )
        }
    }
}


@available(iOS 18, *)
extension SensorKitOnWristRecord {
    /// Creates an on-wrist input from an already-fetched Grove SensorKit value.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        sample: SensorKitOnWristEventSample
    ) throws {
        guard let currentStateStart = sample.onWrist ? sample.onWristDate : sample.offWristDate else {
            throw SensorKitRecordError.missingProviderValue("onWrist.currentStateStart")
        }
        self.init(
            sourceRecordID: sourceRecordID,
            timestamp: sample.timestamp,
            onWrist: sample.onWrist,
            currentStateStart: currentStateStart,
            wristLocation: try Self.side(sample.wristLocation),
            crownOrientation: try Self.side(sample.crownOrientation)
        )
    }

    private static func side(_ value: SRWristDetection.WristLocation) throws -> SensorKitSide {
        switch value {
        case .left: .left
        case .right: .right
        @unknown default:
            throw SensorKitRecordError.unsupportedProviderValue(
                field: "onWrist.wristLocation",
                rawValue: value.rawValue
            )
        }
    }

    private static func side(_ value: SRWristDetection.CrownOrientation) throws -> SensorKitSide {
        switch value {
        case .left: .left
        case .right: .right
        @unknown default:
            throw SensorKitRecordError.unsupportedProviderValue(
                field: "onWrist.crownOrientation",
                rawValue: value.rawValue
            )
        }
    }
}


@available(iOS 18, *)
extension SensorKitDeviceUsageRecord {
    /// Creates a lossless hybrid input from a structured summary and its exact native record.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        report: SRDeviceUsageReport.SafeRepresentation,
        nativeRecording: SensorKitNativeRecording
    ) {
        self.init(
            sourceRecordID: sourceRecordID,
            timestamp: report.timestamp,
            durationSeconds: report.duration,
            totalScreenWakes: report.totalScreenWakes,
            totalUnlocks: report.totalUnlocks,
            totalUnlockDurationSeconds: report.totalUnlockDuration,
            nativeRecording: nativeRecording
        )
    }
}


extension SensorKitVisitRecord {
    /// Creates a visit summary from an already-fetched Grove SensorKit value.
    ///
    /// The location identifier defaults to omission. Supplying it does not itself disclose it: the
    /// conversion context's ``SensorKitLinkableIdentifierPolicy`` still decides.
    public init(
        sourceRecordID: SensorKitSourceRecordID,
        visit: SRVisit.SafeRepresentation,
        locationID: UUID? = nil
    ) throws {
        self.init(
            sourceRecordID: sourceRecordID,
            locationCategory: try Self.locationCategory(visit.locationCategory),
            distanceFromHomeMeters: visit.distanceFromHome,
            arrivalWindow: visit.arrivalDateInterval,
            departureWindow: visit.departureDateInterval,
            locationID: locationID
        )
    }

    private static func locationCategory(
        _ value: SRVisit.LocationCategory
    ) throws -> SensorKitVisitLocationCategory {
        switch value {
        case .home: .home
        case .work: .work
        case .school: .school
        case .gym: .gym
        case .unknown: .unknown
        @unknown default:
            throw SensorKitRecordError.unsupportedProviderValue(
                field: "visit.locationCategory",
                rawValue: value.rawValue
            )
        }
    }
}
#endif

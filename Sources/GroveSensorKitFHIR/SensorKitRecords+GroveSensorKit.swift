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


@available(iOS 18, *)
extension SensorKitCatalog {
    /// The authoritative catalog token for a SensorKit source supported by Grove's FHIR adapter.
    public static func sourceToken(for sensor: SRSensor) -> String? { // swiftlint:disable:this cyclomatic_complexity
        switch sensor {
        case .heartRate: "SRSensor.heartRate"
        case .accelerometer: "SRSensor.accelerometer"
        case .ambientLightSensor: "SRSensor.ambientLightSensor"
        case .ambientPressure: "SRSensor.ambientPressure"
        case .pedometerData: "SRSensor.pedometerData"
        case .wristTemperature: "SRSensor.wristTemperature"
        case .visits: "SRSensor.visits"
        case .onWristState: "SRSensor.onWristState"
        case .deviceUsageReport: "SRSensor.deviceUsageReport"
        case .electrocardiogram: "SRSensor.electrocardiogram"
        case .photoplethysmogram: "SRSensor.photoplethysmogram"
        default: nil
        }
    }

    /// Resolves a Grove SensorKit source directly from Grove's typed sensor facade.
    public func entry(for sensor: some AnySensor) -> SensorKitCatalogEntry? {
        guard let sourceToken = Self.sourceToken(for: sensor.srSensor) else {
            return nil
        }
        return entry(sourceToken: sourceToken)
    }
}


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
    /// `SensorKitECGSession.sessionIdentifier`, `SensorKitECGSession.sessionStates`, and the
    /// per-point SensorKit flags.
    /// Grove neither fetches nor inspects those bytes.
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
        self.init(
            sourceRecordID: sourceRecordID,
            startDate: session.startDate,
            durationSeconds: session.duration,
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
    /// The location identifier defaults to omission. When supplied, conversion retains its exact
    /// canonical UUID only under the caller's governed source-store namespace on a logical Location.
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


@available(iOS 17.4, *)
extension SensorKitPPGRecording {
    /// Creates the registered PPG representation from already-fetched SensorKit values.
    public init(samples: [SRPhotoplethysmogramSample.SafeRepresentation]) throws {
        self.init(records: try samples.map { try Record($0.sample) })
    }

    /// Encodes this recording once and derives the corresponding FHIR summary from those bytes.
    public func sensorKitRecord(
        sourceRecordID: SensorKitSourceRecordID,
        title: String,
        location: SensorKitRecordingLocation,
        admission: SensorRawPayloadAdmission
    ) throws -> SensorKitRecord {
        try prepared().sensorKitRecord(
            sourceRecordID: sourceRecordID,
            title: title,
            location: location,
            admission: admission
        )
    }
}


@available(iOS 17.4, *)
extension SensorKitPPGRecording.Record {
    init(_ sample: SRPhotoplethysmogramSample) throws {
        self.init(
            startDate: sample.startDate,
            nanosecondsSinceStart: sample.nanosecondsSinceStart,
            temperature: sample.temperature?.converted(to: .celsius).value,
            usage: sample.usage.map(\.rawValue),
            opticalSamples: try sample.opticalSamples.map { try .init($0) },
            accelerometerSamples: sample.accelerometerSamples.map { .init($0) }
        )
    }
}


@available(iOS 17.4, *)
extension SensorKitPPGRecording.OpticalSample {
    init(_ sample: SRPhotoplethysmogramOpticalSample) throws {
        let photodiodes = try sample.activePhotodiodeIndexes.map { value -> UInt64 in
            guard let value = UInt64(exactly: value) else {
                throw SensorKitRecordError.unsupportedProviderValue(
                    field: "photoplethysmogram.activePhotodiodeIndexes",
                    rawValue: value
                )
            }
            return value
        }
        guard let emitter = Int64(exactly: sample.emitter),
              let signalIdentifier = Int64(exactly: sample.signalIdentifier) else {
            throw SensorKitRecordError.missingProviderValue("photoplethysmogram.integerRange")
        }
        self.init(
            emitter: emitter,
            activePhotodiodeIndexes: photodiodes,
            signalIdentifier: signalIdentifier,
            nominalWavelength: sample.nominalWavelength.converted(to: .nanometers).value,
            effectiveWavelength: sample.effectiveWavelength.converted(to: .nanometers).value,
            samplingFrequency: sample.samplingFrequency.converted(to: .hertz).value,
            nanosecondsSinceStart: sample.nanosecondsSinceStart,
            conditions: sample.conditions.map(\.rawValue),
            noiseTerms: sample.noiseTerms.map { .init($0) },
            normalizedReflectance: sample.normalizedReflectance
        )
    }
}


@available(iOS 17.4, *)
extension SensorKitPPGRecording.NoiseTerms {
    init(_ terms: SRPhotoplethysmogramOpticalSample.NoiseTerms) {
        self.init(
            whiteNoise: terms.whiteNoise,
            pinkNoise: terms.pinkNoise,
            backgroundNoise: terms.backgroundNoise,
            backgroundNoiseOffset: terms.backgroundNoiseOffset
        )
    }
}


@available(iOS 17.4, *)
extension SensorKitPPGRecording.AccelerometerSample {
    init(_ sample: SRPhotoplethysmogramAccelerometerSample) {
        self.init(
            nanosecondsSinceStart: sample.nanosecondsSinceStart,
            samplingFrequency: sample.samplingFrequency.converted(to: .hertz).value,
            x: sample.x.converted(to: .gravity).value,
            y: sample.y.converted(to: .gravity).value,
            z: sample.z.converted(to: .gravity).value
        )
    }
}
#endif

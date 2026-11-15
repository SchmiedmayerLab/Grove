//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
public import CoreMotion
public import GroveFHIRContract
public import GroveSensorKit


/// One row per sample, each with its own instant, so a batch whose samples are not exactly equidistant stays a
/// faithful recording. ``SensorKitRotationRateRecord`` is the sampled-data form of a batch that is.
extension CMRecordedRotationRateData.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.rotationRate" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .triaxialRotationSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timestamp),
            .number(rotationRate.x),
            .number(rotationRate.y),
            .number(rotationRate.z),
            .text(deviceProductType)
        ]
    }
}


extension CMOdometerData.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.odometer" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .odometerSamples }

    /// The registry's name of the origin device; absent for a value this SDK does not name, which the recording's
    /// required column then refuses.
    private var originDeviceName: RecordingCSVWriter.Field {
        switch originDevice {
        case .unknown: .text("unknown")
        case .local: .text("local")
        case .remote: .text("remote")
        @unknown default: .absent
        }
    }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(startDate),
            .timestamp(endDate),
            .timestamp(gpsDate),
            .number(speed),
            .number(speedAccuracy),
            slope.map(RecordingCSVWriter.Field.number) ?? .absent,
            maxAbsSlope.map(RecordingCSVWriter.Field.number) ?? .absent,
            .number(deltaDistance),
            .number(deltaDistanceAccuracy),
            .number(deltaAltitude),
            .number(verticalAccuracy),
            originDeviceName,
            .text(deviceProductType)
        ]
    }
}
#endif

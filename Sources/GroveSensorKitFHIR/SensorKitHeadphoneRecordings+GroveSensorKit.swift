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
public import SensorKit


@available(iOS 27, *)
extension CMRecordedDeviceMotion.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.headphoneMotion" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .deviceMotionSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timestamp), .timestamp(deliveryTimestamp), .number(uptime), .text(String(identifier)),
            .number(attitude.roll), .number(attitude.pitch), .number(attitude.yaw),
            .number(attitude.rotationMatrix.m11), .number(attitude.rotationMatrix.m12), .number(attitude.rotationMatrix.m13),
            .number(attitude.rotationMatrix.m21), .number(attitude.rotationMatrix.m22), .number(attitude.rotationMatrix.m23),
            .number(attitude.rotationMatrix.m31), .number(attitude.rotationMatrix.m32), .number(attitude.rotationMatrix.m33),
            .number(attitude.quaternion.x), .number(attitude.quaternion.y), .number(attitude.quaternion.z), .number(attitude.quaternion.w),
            .number(rotationRate.x), .number(rotationRate.y), .number(rotationRate.z),
            .number(gravity.x), .number(gravity.y), .number(gravity.z),
            .number(userAcceleration.x), .number(userAcceleration.y), .number(userAcceleration.z),
            .number(magneticField.field.x), .number(magneticField.field.y), .number(magneticField.field.z),
            .integer(Int(magneticField.accuracy.rawValue)), .number(heading), .number(headingAccuracy),
            .integer(sensorLocation.rawValue), .text(deviceProductType)
        ]
    }
}


@available(iOS 27, *)
extension SRHeadphoneSettings.SafeRepresentation: SensorKitTabularSample {
    public static var groveSourceToken: String { "SRSensor.headphoneSettings" }
    public static var groveRecordingFormat: RegisteredRecordingFormat { .headphoneSettingsSamples }

    public func groveRecordingFields(deviceProductType: String) -> [RecordingCSVWriter.Field] {
        [
            .timestamp(timestamp), .integer(Int(adaptiveAudioStrength.rawValue)), .integer(listeningMode.rawValue),
            .integer(personalizedVolumeEnabled.rawValue), .integer(conversationAwarenessEnabled.rawValue),
            .integer(spatialAudioEnabled.rawValue), .integer(personalizedSpatialAudioEnabled.rawValue),
            hearingAssistance.map { .integer($0.hearingAidEnabled.rawValue) } ?? .absent,
            hearingAssistance.map { .integer($0.mediaAssistEnabled.rawValue) } ?? .absent,
            hearingAssistance.map { .integer($0.adjustMediaEnabled.rawValue) } ?? .absent,
            hearingAssistance.map { .integer($0.adjustVoiceEnabled.rawValue) } ?? .absent,
            hearingAssistance.map { .integer($0.hearingProtectionEnabled.rawValue) } ?? .absent,
            hearingAssistance.map { .integer($0.conversationBoostEnabled.rawValue) } ?? .absent,
            hearingAssistance.map { .number($0.hearingAidAmplification) } ?? .absent,
            hearingAssistance.map { .number($0.hearingAidBalance) } ?? .absent,
            hearingAssistance.map { .number($0.hearingAidTone) } ?? .absent,
            hearingAssistance.map { .number($0.ambientNoiseReduction) } ?? .absent,
            .text(deviceProductType)
        ]
    }
}

#endif

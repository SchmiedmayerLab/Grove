//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import CoreMotion
public import GroveFoundation
public import SensorKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// All ``Sensor``s currently known to the `SensorKit` module.
    public static let allKnownSensors: [any AnySensor] = {
        guard SensorKit.isAvailable else {
            return []
        }
        return Array {
            Sensor.onWrist
            Sensor.ambientLight
            Sensor.ambientPressure
            Sensor.heartRate
            Sensor.pedometer
            Sensor.wristTemperature
            if #available(iOS 17.4, *) {
                Sensor.ppg
                Sensor.ecg
            }
            Sensor.visits
            Sensor.deviceUsage
            Sensor.accelerometer
            Sensor.rotationRate
            Sensor.messagesUsage
            Sensor.phoneUsage
            Sensor.keyboardMetrics
            Sensor.siriSpeechMetrics
            Sensor.telephonySpeechMetrics
            Sensor.mediaEvents
            Sensor.faceMetrics
            Sensor.odometer
        }
    }()
}


// MARK: Sensor Definitions

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRWristDetection {
    /// A sensor that describes the watch’s position on the wrist.
    @inlinable public static var onWrist: Sensor<SRWristDetection> {
        Sensor(
            srSensor: .onWristState,
            displayName: "On-Wrist State",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRAmbientLightSample {
    /// A sensor that provides ambient light information.
    @inlinable public static var ambientLight: Sensor<SRAmbientLightSample> {
        Sensor(
            srSensor: .ambientLightSensor,
            displayName: "Ambient Light",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == CMRecordedPressureData {
    /// A sensor that provides pressure and temperature metrics.
    @inlinable public static var ambientPressure: Sensor<CMRecordedPressureData> {
        Sensor(
            srSensor: .ambientPressure,
            displayName: "Ambient Pressure",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .array
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == CMHighFrequencyHeartRateData {
    /// A sensor that provides the user’s heart rate data.
    @inlinable public static var heartRate: Sensor<CMHighFrequencyHeartRateData> {
        Sensor(
            srSensor: .heartRate,
            displayName: "Heart Rate",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == CMPedometerData {
    /// A sensor that provides information about the user’s steps.
    @inlinable public static var pedometer: Sensor<CMPedometerData> {
        Sensor(
            srSensor: .pedometerData,
            displayName: "Pedometer",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRWristTemperatureSession {
    /// A sensor that provides wrist temperature while the user sleeps.
    @inlinable public static var wristTemperature: Sensor<SRWristTemperatureSession> {
        Sensor(
            srSensor: .wristTemperature,
            displayName: "Wrist Temperature",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 17.4, *)
@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRPhotoplethysmogramSample {
    /// A sensor that streams sample PPG sensor data.
    @inlinable public static var ppg: Sensor<SRPhotoplethysmogramSample> {
        Sensor(
            srSensor: .photoplethysmogram,
            displayName: "PPG",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .array
        )
    }
}

@available(iOS 17.4, *)
@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRElectrocardiogramSample {
    /// A sensor that streams sample ECG sensor data.
    @inlinable public static var ecg: Sensor<SRElectrocardiogramSample> {
        Sensor(
            srSensor: .electrocardiogram,
            displayName: "ECG",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .array
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRVisit {
    /// A sensor that provides information about frequently visited locations.
    @inlinable public static var visits: Sensor<SRVisit> {
        Sensor(
            srSensor: .visits,
            displayName: "Visits",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRDeviceUsageReport {
    /// A sensor that provides information about device usage.
    @inlinable public static var deviceUsage: Sensor<SRDeviceUsageReport> {
        Sensor(
            srSensor: .deviceUsageReport,
            displayName: "Device Usage Report",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == CMRecordedAccelerometerData {
    /// A sensor that provides acceleration motion data.
    @inlinable public static var accelerometer: Sensor<CMRecordedAccelerometerData> {
        Sensor(
            srSensor: .accelerometer,
            displayName: "Accelerometer",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .array
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == CMRecordedRotationRateData {
    /// A sensor that provides rotation motion data.
    @inlinable public static var rotationRate: Sensor<CMRecordedRotationRateData> {
        Sensor(
            srSensor: .rotationRate,
            displayName: "Rotation Rate",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .array
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRMessagesUsageReport {
    /// A sensor that provides information about use of the Messages app.
    @inlinable public static var messagesUsage: Sensor<SRMessagesUsageReport> {
        Sensor(
            srSensor: .messagesUsageReport,
            displayName: "Messages Usage",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRPhoneUsageReport {
    /// A sensor that reports the amount of time that the user is on phone calls.
    @inlinable public static var phoneUsage: Sensor<SRPhoneUsageReport> {
        Sensor(
            srSensor: .phoneUsageReport,
            displayName: "Phone Usage",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRKeyboardMetrics {
    /// A sensor that provides information about keyboard usage.
    @inlinable public static var keyboardMetrics: Sensor<SRKeyboardMetrics> {
        Sensor(
            srSensor: .keyboardMetrics,
            displayName: "Keyboard Metrics",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRSpeechMetrics {
    /// A sensor that provides data describing a user’s speech to Siri.
    @inlinable public static var siriSpeechMetrics: Sensor<SRSpeechMetrics> {
        Sensor(
            srSensor: .siriSpeechMetrics,
            displayName: "Speech Metrics",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRSpeechMetrics {
    /// A sensor that provides data describing speech during phone calls.
    @inlinable public static var telephonySpeechMetrics: Sensor<SRSpeechMetrics> {
        Sensor(
            srSensor: .telephonySpeechMetrics,
            displayName: "Telephony Speech Metrics",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRMediaEvent {
    /// A sensor that provides information about interactions with media, such as images and videos, in messaging apps.
    @inlinable public static var mediaEvents: Sensor<SRMediaEvent> {
        Sensor(
            srSensor: .mediaEvents,
            displayName: "Media Events",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == SRFaceMetrics {
    /// A sensor that provides data describing a user’s face.
    @inlinable public static var faceMetrics: Sensor<SRFaceMetrics> {
        Sensor(
            srSensor: .faceMetrics,
            displayName: "Face Metrics",
            dataQuarantineDuration: .days(7),
            sensorKitFetchReturnType: .object
        )
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Sensor where Sample == CMOdometerData {
    /// A sensor that provides information about speed and slope.
    @inlinable public static var odometer: Sensor<CMOdometerData> {
        Sensor(
            srSensor: .odometer,
            displayName: "Odometer (Speed and Slope)",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .object
        )
    }
}


// MARK: Utils

@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSensor {
    var sensor: (any AnySensor)? {
        if self == .ambientLightSensor {
            Sensor.ambientLight
        } else if self == .accelerometer {
            Sensor.accelerometer
        } else if self == .rotationRate {
            Sensor.rotationRate
        } else if self == .visits {
            Sensor.visits
        } else if self == .pedometerData {
            Sensor.pedometer
        } else if self == .deviceUsageReport {
            Sensor.deviceUsage
        } else if self == .messagesUsageReport {
            Sensor.messagesUsage
        } else if self == .phoneUsageReport {
            Sensor.phoneUsage
        } else if self == .onWristState {
            Sensor.onWrist
        } else if self == .keyboardMetrics {
            Sensor.keyboardMetrics
        } else if self == .siriSpeechMetrics {
            Sensor.siriSpeechMetrics
        } else if self == .telephonySpeechMetrics {
            Sensor.telephonySpeechMetrics
        } else if self == .ambientPressure {
            Sensor.ambientPressure
        } else if self == .mediaEvents {
            Sensor.mediaEvents
        } else if self == .wristTemperature {
            Sensor.wristTemperature
        } else if self == .heartRate {
            Sensor.heartRate
        } else if self == .faceMetrics {
            Sensor.faceMetrics
        } else if self == .odometer {
            Sensor.odometer
        } else if #available(iOS 17.4, *), self == .electrocardiogram {
            Sensor.ecg
        } else if #available(iOS 17.4, *), self == .photoplethysmogram {
            Sensor.ppg
        } else {
            nil
        }
    }
}

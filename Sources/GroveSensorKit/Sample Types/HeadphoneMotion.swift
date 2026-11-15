//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)

public import CoreMotion
public import Foundation
public import GroveFoundation
import SensorKit


// `CMRecordedDeviceMotion` and the headphone motion sensor exist only in the iOS 27 SDK.
#if compiler(>=6.4)
@available(iOS 27, *)
extension CMRecordedDeviceMotion: SensorKitSampleProtocol {
    /// Immutable public motion facts; the mutable CMAttitude object never crosses the fetch boundary.
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        public struct Attitude: Hashable, Sendable {
            public let roll: Double
            public let pitch: Double
            public let yaw: Double
            public let rotationMatrix: RotationMatrix
            public let quaternion: SIMD4<Double>

            init(_ value: CMAttitude) {
                roll = value.roll
                pitch = value.pitch
                yaw = value.yaw
                rotationMatrix = RotationMatrix(value.rotationMatrix)
                quaternion = SIMD4(value.quaternion.x, value.quaternion.y, value.quaternion.z, value.quaternion.w)
            }
        }

        public struct RotationMatrix: Hashable, Sendable {
            public let m11: Double
            public let m12: Double
            public let m13: Double
            public let m21: Double
            public let m22: Double
            public let m23: Double
            public let m31: Double
            public let m32: Double
            public let m33: Double

            init(_ value: CMRotationMatrix) {
                m11 = value.m11
                m12 = value.m12
                m13 = value.m13
                m21 = value.m21
                m22 = value.m22
                m23 = value.m23
                m31 = value.m31
                m32 = value.m32
                m33 = value.m33
            }
        }

        public struct MagneticField: Hashable, Sendable {
            public let field: SIMD3<Double>
            public let accuracy: CMMagneticFieldCalibrationAccuracy

            init(_ value: CMCalibratedMagneticField) {
                field = SIMD3(value.field.x, value.field.y, value.field.z)
                accuracy = value.accuracy
            }
        }

        public let timestamp: Date
        public let deliveryTimestamp: Date
        public let uptime: TimeInterval
        public let identifier: UInt64
        public let attitude: Attitude
        public let rotationRate: CMRotationRate
        public let gravity: CMAcceleration
        public let userAcceleration: CMAcceleration
        public let magneticField: MagneticField
        public let heading: Double
        public let headingAccuracy: Double
        public let sensorLocation: CMDeviceMotion.SensorLocation

        public var timeRange: Range<Date> { timestamp..<timestamp }

        init(timestamp: Date, sample: CMRecordedDeviceMotion) {
            self.timestamp = sample.startDate
            deliveryTimestamp = timestamp
            uptime = sample.timestamp
            identifier = sample.identifier
            attitude = Attitude(sample.attitude)
            rotationRate = sample.rotationRate
            gravity = sample.gravity
            userAcceleration = sample.userAcceleration
            magneticField = MagneticField(sample.magneticField)
            heading = sample.heading
            headingAccuracy = sample.headingAccuracy
            sensorLocation = sample.sensorLocation
        }
    }

    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: CMRecordedDeviceMotion)>
    ) -> [SafeRepresentation] {
        samples.map { SafeRepresentation(timestamp: $0.timestamp, sample: $0.sample) }
    }
}


@available(iOS 27, *)
extension Sensor where Sample == CMRecordedDeviceMotion {
    /// Motion recorded by the headphone source, retaining all public orientation and motion facts.
    @inlinable public static var headphoneMotion: Sensor<CMRecordedDeviceMotion> {
        Sensor(
            srSensor: .headphoneMotion,
            displayName: "Headphone Motion",
            dataQuarantineDuration: .hours(24),
            sensorKitFetchReturnType: .array
        )
    }
}
#endif

#endif

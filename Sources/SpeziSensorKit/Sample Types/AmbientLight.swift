//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SensorKit


@available(iOS 17, *)
extension SRAmbientLightSample: SensorKitSampleProtocol {
    public struct SafeRepresentation: SensorKitSampleSafeRepresentation {
        /// The point in time when the system recorded the measurement
        public let timestamp: Date
        /// The sample’s luminous flux.
        public let lux: Measurement<UnitIlluminance>
        /// The light’s location relative to the sensor.
        public let placement: SRAmbientLightSample.SensorPlacement
        /// A coordinate pair that describes the sample’s light brightness and tint.
        ///
        /// - Note: Chromaticity is only valid on supporting devices. If not supported, the values will be zero.
        public let chromacity: SRAmbientLightSample.Chromaticity
        
        @inlinable public var timeRange: Range<Date> {
            timestamp..<timestamp
        }
        
        @inlinable
        init(timestamp: Date, sample: SRAmbientLightSample) {
            self.timestamp = timestamp
            self.lux = sample.lux
            self.placement = sample.placement
            self.chromacity = sample.chromaticity
        }
    }
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRAmbientLightSample)>
    ) -> [SafeRepresentation] {
        samples.map { .init(timestamp: $0, sample: $1) }
    }
}


@available(iOS 17, *)
extension SRAmbientLightSample.Chromaticity: @retroactive Equatable, @retroactive Hashable {
    @inlinable
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y
    }
    
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}


@available(iOS 17, *)
extension SRAmbientLightSample.Chromaticity: @retroactive CustomStringConvertible {
    public var description: String {
        "\(Self.self)(x: \(x), y: \(y))"
    }
}

@available(iOS 17, *)
extension SRAmbientLightSample.SensorPlacement: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            "unknown"
        case .frontTop:
            "frontTop"
        case .frontBottom:
            "frontBottom"
        case .frontRight:
            "frontRight"
        case .frontLeft:
            "frontLeft"
        case .frontTopRight:
            "frontTopRight"
        case .frontTopLeft:
            "frontTopLeft"
        case .frontBottomRight:
            "frontBottomRight"
        case .frontBottomLeft:
            "frontBottomLeft"
        @unknown default:
            "unknown<\(rawValue)>"
        }
    }
}

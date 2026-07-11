//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import SensorKit


// MARK: SRAbsoluteTime

extension SRAbsoluteTime {
    /// Creates an `SRAbsoluteTime` from a `Date`
    @inlinable
    public init(_ date: Date) {
        self = .fromCFAbsoluteTime(_cf: date.timeIntervalSinceReferenceDate)
    }
}

extension Date {
    /// Creates a `Date` from an `SRAbsoluteTime`
    @inlinable
    public init(_ time: SRAbsoluteTime) {
        self.init(timeIntervalSinceReferenceDate: time.toCFAbsoluteTime())
    }
}

extension SRAbsoluteTime: @retroactive Comparable {
    @inlinable
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}


// MARK: Other

@available(iOS 18, macOS 15, watchOS 11, *)
extension SRSensorReader {
    /// Creates an `SRSensorReader` from an ``AnySensor``.
    @inlinable
    convenience init(_ sensor: some AnySensor) {
        self.init(sensor: sensor.srSensor)
    }
}

@available(iOS 17.4, *)
extension SRElectrocardiogramData.Flags: @retroactive Hashable {
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

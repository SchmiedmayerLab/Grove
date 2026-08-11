//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import Foundation
public import SensorKit


// MARK: On-Wrist Detection

@available(iOS 18, macOS 15, watchOS 11, *)
extension SRWristDetection: SensorKitSampleProtocol {
    public typealias SafeRepresentation = SensorKitOnWristEventSample
    
    @inlinable
    public static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SRWristDetection)>
    ) -> [SensorKitOnWristEventSample] {
        samples.map { .init(timestamp: $0, sample: $1) }
    }
}


/// An On-Wrist Event collected by SensorKit.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct SensorKitOnWristEventSample: SensorKitSampleSafeRepresentation {
    /// The date when this sample was collected
    public let timestamp: Date
    
    @inlinable public var timeRange: Range<Date> {
        timestamp..<timestamp
    }
    
    /// Whether the watch was on the user's wrist.
    public let onWrist: Bool
    public let wristLocation: SRWristDetection.WristLocation
    public let crownOrientation: SRWristDetection.CrownOrientation
    
    /// Start date of the recent on-wrist state.
    ///
    /// When the state changes from off-wrist to on-wrist, ``onWristDate`` would be updated to the current date, and ``offWristDate`` would remain the same.
    /// When the state changes from on-wrist to off-wrist, ``offWristDate`` would be updated to the current date, and ``onWristDate`` would remain the same.
    public let onWristDate: Date?
    
    /// Start date of the recent off-wrist state.
    ///
    /// When the state changes from off-wrist to on-wrist, ``onWristDate`` would be updated to the current date, and ``offWristDate`` would remain the same.
    /// When the state changes from on-wrist to off-wrist, ``offWristDate`` would be updated to the current date, and ``onWristDate`` would remain the same.
    public let offWristDate: Date?
    
    @inlinable
    init(timestamp: Date, sample: SRWristDetection) {
        self.timestamp = timestamp
        self.onWrist = sample.onWrist
        self.wristLocation = sample.wristLocation
        self.crownOrientation = sample.crownOrientation
        self.onWristDate = sample.onWristDate
        self.offWristDate = sample.offWristDate
    }
}


extension SRWristDetection.WristLocation: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .left:
            "left"
        case .right:
            "right"
        @unknown default:
            "unknown<\(rawValue)>"
        }
    }
}

extension SRWristDetection.CrownOrientation: @retroactive CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .left:
            "left"
        case .right:
            "right"
        @unknown default:
            "unknown<\(rawValue)>"
        }
    }
}

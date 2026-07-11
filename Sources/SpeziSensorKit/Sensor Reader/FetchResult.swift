//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
import SensorKit
import SpeziFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// A batch of samples returned by SensorKit
    public struct FetchResult<Sample: SensorKitSampleProtocol>: Hashable {
        /// The SensorKit framework's timestamp associated with this batch of samples
        public let sensorKitTimestamp: Date
        /// The samples.
        public let samples: [Sample]
        
        @inlinable
        init(_ fetchResult: SRFetchResult<AnyObject>, for sensor: Sensor<Sample>) {
            sensorKitTimestamp = Date(fetchResult.timestamp)
            samples = switch sensor.sensorKitFetchReturnType {
            case .object:
                [unsafeDowncast(fetchResult.sample, to: Sample.self)]
            case .array:
                Array(_immutableCocoaArray: unsafeDowncast(fetchResult.sample, to: NSArray.self))
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit.FetchResult: RandomAccessCollection {
    @inlinable public var startIndex: Int {
        samples.startIndex
    }
    
    @inlinable public var endIndex: Int {
        samples.endIndex
    }
    
    @inlinable
    public func index(after idx: Int) -> Int {
        samples.index(after: idx)
    }
    
    @inlinable
    public func index(before idx: Int) -> Int {
        samples.index(before: idx)
    }
    
    @inlinable
    public func makeIterator() -> [Sample].Iterator {
        samples.makeIterator()
    }
    
    @inlinable
    public subscript(position: Int) -> Sample {
        samples[position]
    }
}

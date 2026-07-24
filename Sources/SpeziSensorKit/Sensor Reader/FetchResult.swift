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
    /// Thrown by ``FetchResult/init`` if the input `SRFetchResult`'s carried data fails to be casted into ``Sensor``'s expected type.
    struct FetchResultTypeError: Error, CustomStringConvertible {
        let sensor: any AnySensor
        let expectedType: Any.Type
        let actualType: Any.Type
        
        var description: String {
            "Invalid SRFetchResult data type for \(sensor); expected \(expectedType), but got \(actualType)"
        }
    }
    
    
    /// A batch of samples returned by SensorKit
    public struct FetchResult<Sample: SensorKitSampleProtocol>: Hashable {
        /// The SensorKit framework's timestamp associated with this batch of samples
        public let sensorKitTimestamp: Date
        /// The samples.
        public let samples: [Sample]
        
        init(_ fetchResult: SRFetchResult<AnyObject>, for sensor: Sensor<Sample>) throws {
            sensorKitTimestamp = Date(fetchResult.timestamp)
            // IMPORTANT: accessing the `SRFetchResult.sample` is where SensorKit (if needed) will lazily materialize the batch;
            // for some sensors (eg PPG, or motion), this getter will perform actual O(n) decoding work, delegated to the sensor's
            // respective underlying framework.
            let object: AnyObject = fetchResult.sample
            switch sensor.sensorKitFetchReturnType {
            case .object:
                guard let sample = object as? Sample else {
                    throw SensorKit.FetchResultTypeError(sensor: sensor, expectedType: Sample.self, actualType: type(of: object))
                }
                samples = [sample]
            case .array:
                guard let samples = object as? [Sample] else {
                    throw SensorKit.FetchResultTypeError(sensor: sensor, expectedType: [Sample].self, actualType: type(of: object))
                }
                self.samples = samples
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

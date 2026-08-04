//
// This source file is part of the SpeziSensorKit open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import SensorKit
import SpeziFoundation


/// A `Sendable` representation of a data sample obtained from SensorKit.
public protocol SensorKitSampleSafeRepresentation: Hashable, Sendable {
    /// The sample's time range.
    ///
    /// If the sample represents a single point in time, the range will be empty.
    ///
    /// Depending on the specific sensor this sample originates from, the timestamp represents either the actual time the sample was recorded, or the time it was added to SensorKit.
    var timeRange: Range<Date> { get }
}


/// A type that is returned from a SensorKit query.
///
/// - Important: For any type that declares conformance to  ``SensorKitSampleProtocol``, the ``SafeRepresentationProcessingInput`` type **must** be equal to the type itself.
///     Failure to do so is a programmer error and will result in the program crashing at runtime.
///     This associatedtype is required to work around type system limitations.
///
/// ## Topics
///
/// ### Associated Types
/// - ``SafeRepresentation``
/// - ``SafeRepresentationProcessingInput``
///
/// ### Static Methods
/// - ``processIntoSafeRepresentation(_:)``
///
/// ### Other Types
/// - ``SensorKitSampleSafeRepresentation``
/// - ``DefaultSensorKitSampleSafeRepresentation``
public protocol SensorKitSampleProtocol: AnyObject, Hashable, SendableMetatype {
    /// A "safe" `Sendable` representation of the type.
    ///
    /// This is required because most SensorKit types are not Sendable and can only be used on the specific DispatchQueue used internally by SensorKit.
    associatedtype SafeRepresentation: SensorKitSampleSafeRepresentation
    
    /// The sample input when processing samples of this type into their safe representation.
    associatedtype SafeRepresentationProcessingInput: AnyObject, Hashable = Self
    
    /// Processes a batch of samples into their safe representation.
    @inlinable
    static func processIntoSafeRepresentation(
        _ samples: some Sequence<(timestamp: Date, sample: SafeRepresentationProcessingInput)>
    ) throws -> [SafeRepresentation]
}


extension SensorKitSampleProtocol where SafeRepresentation == SafeRepresentationProcessingInput {
    @inlinable
    public static func processIntoSafeRepresentation( // swiftlint:disable:this missing_docs
        _ samples: some Sequence<(timestamp: Date, sample: SafeRepresentationProcessingInput)>
    ) -> [SafeRepresentation] {
        samples.map(\.sample)
    }
}

extension SensorKitSampleProtocol where SafeRepresentation == DefaultSensorKitSampleSafeRepresentation<SafeRepresentationProcessingInput> {
    @inlinable
    public static func processIntoSafeRepresentation( // swiftlint:disable:this missing_docs
        _ samples: some Sequence<(timestamp: Date, sample: SafeRepresentationProcessingInput)>
    ) -> [SafeRepresentation] {
        samples.map { .init(timestamp: $0, sample: $1) }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SensorKit)

import FHIRModelsExtensions
import Foundation
public import GroveSensorKit
public import ModelsR4
import SensorKit


/// A SensorKit sample that converts into a FHIR `Observation`.
@available(iOS 18, *)
public protocol SensorKitObservationConvertible {
    /// The Grove profile the emitted observation declares and satisfies.
    static var profile: FHIRPrimitive<Canonical> { get }
    /// The observation's category.
    static var category: CodeableConcept { get }

    /// Feeds the digest that becomes the observation's identifier.
    ///
    /// Combine every value the record ships — the observation's own elements, plus the
    /// payload of any batch it derives from — and nothing else. A value the record ships
    /// but the digest omits lets two differing samples collide under `ifNoneExist`, where
    /// the server keeps the first and discards the second; a value the digest covers but
    /// the record never carries forges a duplicate of something identical on the wire.
    func hashIdentifierContent(into hasher: inout SensorKitSampleIDHasher)

    /// Builds the observation body: code, effective time, value, and components.
    func buildObservation(_ observation: inout Observation) throws
}


/// An error raised while converting a SensorKit sample into FHIR.
public enum SensorKitConversionError: Error, CustomStringConvertible {
    /// SensorKit reported a value Grove's published vocabulary does not cover — a case
    /// Apple added after this mapping was written.
    ///
    /// Dropping it would make the resource silently claim the value was absent, so the
    /// conversion fails instead and the caller decides what to do with the sample.
    case unrecognizedPlatformValue(concept: String, rawValue: Int)

    public var description: String {
        switch self {
        case let .unrecognizedPlatformValue(concept, rawValue):
            "SensorKit reported a \(concept) value this mapping does not cover (raw value \(rawValue))"
        }
    }
}


@available(iOS 18, *)
extension SensorKitObservationConvertible {
    /// The id of the contained recording device, stable because containment is scoped to
    /// the one observation that contains it.
    static var containedDeviceID: String {
        "sensor-device"
    }

    /// Converts the sample into an `Observation` carrying Grove's shared envelope:
    /// profile declaration, keyed content-derived identifier, category, subject, the
    /// recording device, the batches it derives from, and the issue time.
    ///
    /// - parameter identifierKey: The deployment's identifier key. See ``SensorKitIdentifierKey``.
    /// - parameter subject: The participant the observation is about.
    /// - parameter device: The recording watch or phone, contained in the observation.
    /// - parameter derivedFrom: The raw sensor batches this observation summarizes.
    /// - parameter issued: When the record was made available.
    public func observation(
        identifierKey: SensorKitIdentifierKey,
        subject: Reference,
        device: Device? = nil,
        derivedFrom: [Reference] = [],
        issued: Date = Date()
    ) throws -> Observation {
        var observation = Observation(
            code: CodeableConcept(),
            status: FHIRPrimitive(.final)
        )
        observation.meta = Meta(profile: [Self.profile])
        var hasher = SensorKitSampleIDHasher(key: identifierKey)
        hashIdentifierContent(into: &hasher)
        observation.identifier = [
            Identifier(
            system: GroveSensorKitVocabulary.sampleId,
            value: hasher.finalize().uuidString.asFHIRStringPrimitive()
        )
        ]
        observation.category = [Self.category]
        observation.subject = subject
        if var device {
            device.id = Self.containedDeviceID.asFHIRStringPrimitive()
            observation.contained = [ResourceProxy(with: device)]
            observation.device = Reference(reference: "#\(Self.containedDeviceID)".asFHIRStringPrimitive())
        }
        observation.derivedFrom = derivedFrom.isEmpty ? nil : derivedFrom
        observation.issued = FHIRPrimitive(try Instant(date: issued))
        try buildObservation(&observation)
        return observation
    }

    func sampleTypeCoding(_ sensorIdentifier: String, _ display: String) -> Coding {
        Coding(
            code: sensorIdentifier.asFHIRStringPrimitive(),
            display: display.asFHIRStringPrimitive(),
            system: GroveSensorKitVocabulary.sampleType
        )
    }
}


// MARK: Coded Values

@available(iOS 18, *)
extension SRWristDetection.WristLocation {
    var groveCode: (code: String, display: String) {
        get throws {
            switch self {
            case .left:
                ("left", "Left")
            case .right:
                ("right", "Right")
            @unknown default:
                throw SensorKitConversionError.unrecognizedPlatformValue(concept: "wrist location", rawValue: rawValue)
            }
        }
    }
}


@available(iOS 18, *)
extension SRWristDetection.CrownOrientation {
    var groveCode: (code: String, display: String) {
        get throws {
            switch self {
            case .left:
                ("left", "Left")
            case .right:
                ("right", "Right")
            @unknown default:
                throw SensorKitConversionError.unrecognizedPlatformValue(concept: "crown orientation", rawValue: rawValue)
            }
        }
    }
}


@available(iOS 18, *)
extension SRVisit.LocationCategory {
    var groveCode: (code: String, display: String) {
        get throws {
            switch self {
            case .home:
                ("home", "Home")
            case .work:
                ("work", "Work")
            case .school:
                ("school", "School")
            case .gym:
                ("gym", "Gym")
            case .unknown:
                ("unknown", "Unknown")
            @unknown default:
                throw SensorKitConversionError.unrecognizedPlatformValue(concept: "visit location category", rawValue: rawValue)
            }
        }
    }
}

#endif

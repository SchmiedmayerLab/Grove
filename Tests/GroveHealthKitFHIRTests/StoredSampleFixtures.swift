//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import HealthKit
import ObjectiveC


/// TEST-ONLY. Builds HealthKit samples the way the store hands them back: with a chosen UUID, an
/// attributable `HKSourceRevision`, and (for the series classes HealthKit offers no synthetic
/// initializer for) chosen dates, device and metadata.
///
/// HealthKit's public factories mint a fresh UUID and attribute every sample to the running
/// process, so no test can otherwise pin a graph whose identities derive from the UUID, or one that
/// carries writer and writer-host Device entries. The helper writes HealthKit's private ivars
/// through key-value coding (`_UUID`, `_sourceRevision`, ...); such a sample behaves like a fetched
/// one, including through an `NSKeyedArchiver` round trip. `StoredSampleFixturesTests` fails, and
/// never skips, the moment HealthKit stops honoring a key, so a silent regression into
/// process-attributed samples cannot hide behind green goldens.
///
/// Nothing here may be used outside the test target.
enum StoredSampleFixtures {
    /// The writer a stored sample is attributed to, as `HKSourceRevision` states it.
    struct Writer: Sendable {
        /// A source without a name or bundle identifier, which the converter treats as no writer at all; what a
        /// sample built in-process reports when nothing attributes it.
        static let unattributed = Writer(name: "", bundleIdentifier: "", version: nil, productType: nil)

        var name: String
        var bundleIdentifier: String
        var version: String?
        var productType: String?
        var operatingSystemVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
    }

    /// The facts of a sample whose class has no public initializer (`HKHeartbeatSeriesSample`,
    /// `HKElectrocardiogram`, `HKWorkoutRoute`).
    struct SeriesShape: Sendable {
        var uuid: UUID
        var start: Date
        var end: Date
        var device: HKDevice?
        var metadata: [String: any Sendable]?  // swiftlint:disable:this discouraged_optional_collection
        var writer: Writer
    }

    #if !os(watchOS)
    /// The FHIR resource a provider issued, as an `HKClinicalRecord` carries it.
    struct ClinicalResource {
        var version: HKFHIRVersion
        var type: HKFHIRResourceType
        var identifier: String
        var data: Data
    }
    #endif

    enum FixtureError: Error, CustomStringConvertible {
        case classNotConstructible(String)
        case keyNotHonored(key: String, class: String)

        var description: String {
            switch self {
            case .classNotConstructible(let name):
                "HealthKit refused to allocate a bare \(name); the stored-sample fixtures need a new strategy"
            case let .keyNotHonored(key, name):
                "\(name) no longer reads back the value written to '\(key)'; the stored-sample fixtures need a new strategy"
            }
        }
    }

    private static let objectKeys = ["UUID", "sourceRevision", "device", "metadata"]
    private static let sampleKeys = ["sampleType", "startTimestamp", "endTimestamp"]

    /// An `HKSource` naming the writing application; HealthKit itself only ever vends one for the running process.
    static func source(name: String, bundleIdentifier: String) throws -> HKSource {
        let source = try allocate(HKSource.self)
        try write(name, to: "name", of: source)
        try write(bundleIdentifier, to: "bundleIdentifier", of: source)
        return unsafeDowncast(source, to: HKSource.self)
    }

    static func sourceRevision(_ writer: Writer) throws -> HKSourceRevision {
        HKSourceRevision(
            source: try source(name: writer.name, bundleIdentifier: writer.bundleIdentifier),
            version: writer.version,
            productType: writer.productType,
            operatingSystemVersion: writer.operatingSystemVersion
        )
    }

    /// `sample` with the UUID the store would have given it and, when `writer` is given, its source revision;
    /// every other fact stays as built.
    ///
    /// Without a writer the sample keeps the revision its factory gave it, which names no source at all. That is
    /// the only shape `HKCorrelation`'s initializer admits for its objects: one that already states a writer is
    /// validated against the process's default source, which a test process does not have.
    static func stored<Sample: HKSample>(_ sample: Sample, uuid: UUID, writer: Writer? = nil) throws -> Sample {
        try write(uuid, to: "UUID", of: sample)
        if let writer {
            try write(try sourceRevision(writer), to: "sourceRevision", of: sample)
        }
        try verify(sample, uuid: uuid, writer: writer)
        return sample
    }

    /// A bare instance of a sample class without a public initializer, carrying exactly `shape`.
    static func seriesSample<Sample: HKSample>(_ type: Sample.Type, sampleType: HKSampleType, shape: SeriesShape) throws -> Sample {
        let object = try allocate(type)
        try write(sampleType, to: "sampleType", of: object)
        try write(NSNumber(value: shape.start.timeIntervalSinceReferenceDate), to: "startTimestamp", of: object)
        try write(NSNumber(value: shape.end.timeIntervalSinceReferenceDate), to: "endTimestamp", of: object)
        try write(shape.device, to: "device", of: object)
        try write(shape.metadata, to: "metadata", of: object)
        let sample = try stored(unsafeDowncast(object, to: type), uuid: shape.uuid, writer: shape.writer)
        guard sample.sampleType == sampleType, sample.startDate == shape.start, sample.endDate == shape.end else {
            throw FixtureError.keyNotHonored(key: "sampleType/startTimestamp/endTimestamp", class: String(describing: type))
        }
        guard sample.device == shape.device, (sample.metadata ?? [:]).keys.sorted() == (shape.metadata ?? [:]).keys.sorted() else {
            throw FixtureError.keyNotHonored(key: "device/metadata", class: String(describing: type))
        }
        return sample
    }

    #if !os(watchOS)
    /// An `HKClinicalRecord` carrying `resource` as the provider's FHIR resource, the way a fetched record carries it;
    /// HealthKit offers no initializer for either class. Fails unless the record reads every value back.
    static func clinicalRecord(
        _ type: HKClinicalTypeIdentifier,
        shape: SeriesShape,
        displayName: String,
        resource: ClinicalResource
    ) throws -> HKClinicalRecord {
        let fhirResource = try allocate(HKFHIRResource.self)
        try write(resource.version, to: "FHIRVersion", of: fhirResource)
        try write(resource.type.rawValue, to: "resourceType", of: fhirResource)
        try write(resource.identifier, to: "identifier", of: fhirResource)
        try write(resource.data, to: "data", of: fhirResource)
        let record = try seriesSample(HKClinicalRecord.self, sampleType: HKClinicalType(type), shape: shape)
        try write(displayName, to: "displayName", of: record)
        try write(fhirResource, to: "FHIRResource", of: record)
        guard record.displayName == displayName,
              record.fhirResource?.data == resource.data,
              record.fhirResource?.resourceType == resource.type,
              record.fhirResource?.fhirVersion.fhirRelease == resource.version.fhirRelease else {
            throw FixtureError.keyNotHonored(key: "displayName/FHIRResource", class: String(describing: HKClinicalRecord.self))
        }
        return record
    }
    #endif

    /// Whether every private ivar the fixtures write still exists, checked before a single value is written.
    static func privateStorageIsPresent() -> Bool {
        (objectKeys.allSatisfy { class_getInstanceVariable(HKObject.self, "_\($0)") != nil })
            && (sampleKeys.allSatisfy { class_getInstanceVariable(HKSample.self, "_\($0)") != nil })
            && ["name", "bundleIdentifier"].allSatisfy { class_getInstanceVariable(HKSource.self, "_\($0)") != nil }
    }

    private static func allocate(_ type: AnyClass) throws -> NSObject {
        guard let object = class_createInstance(type, 0) as? NSObject else {
            throw FixtureError.classNotConstructible(String(describing: type))
        }
        return object
    }

    private static func write(_ value: Any?, to key: String, of object: NSObject) throws {
        guard class_getInstanceVariable(type(of: object), "_\(key)") != nil else {
            throw FixtureError.keyNotHonored(key: key, class: String(describing: type(of: object)))
        }
        object.setValue(value, forKey: key)
    }

    private static func verify(_ sample: HKSample, uuid: UUID, writer: Writer?) throws {
        let name = String(describing: type(of: sample))
        guard sample.uuid == uuid else {
            throw FixtureError.keyNotHonored(key: "UUID", class: name)
        }
        guard let writer else {
            return
        }
        let revision = sample.sourceRevision
        guard revision.source.name == writer.name,
              revision.source.bundleIdentifier == writer.bundleIdentifier,
              revision.version == writer.version,
              revision.productType == writer.productType,
              revision.operatingSystemVersion.majorVersion == writer.operatingSystemVersion.majorVersion,
              revision.operatingSystemVersion.minorVersion == writer.operatingSystemVersion.minorVersion,
              revision.operatingSystemVersion.patchVersion == writer.operatingSystemVersion.patchVersion else {
            throw FixtureError.keyNotHonored(key: "sourceRevision", class: name)
        }
    }
}

#endif

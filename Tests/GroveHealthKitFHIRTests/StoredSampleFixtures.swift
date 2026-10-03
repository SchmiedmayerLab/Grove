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


/// TEST-ONLY. An `HKElectrocardiogram` that states its whole reading itself.
///
/// HealthKit keeps an ECG's voltage count and sampling frequency in a C++ reading key-value coding cannot reach,
/// and derives its classification from a private enumeration, so a stored ECG answers those five properties
/// from the reading `StoredSampleFixtures.electrocardiogram(shape:reading:)` attaches. Every other fact lives
/// where HealthKit keeps it.
final class StoredElectrocardiogram: HKElectrocardiogram, @unchecked Sendable {
    /// What an ECG reports about its recording.
    struct Reading: Sendable {
        var classification: HKElectrocardiogram.Classification
        var symptomsStatus: HKElectrocardiogram.SymptomsStatus
        var numberOfVoltageMeasurements: Int
        var averageHeartRate: HKQuantity?
        var samplingFrequency: HKQuantity?
    }

    /// The reading, as an object the runtime can associate with the instance.
    private final class Statement: NSObject {
        let reading: Reading

        init(_ reading: Reading) {
            self.reading = reading
        }
    }

    /// The association key; only its address matters.
    nonisolated(unsafe) private static var readingKey: UInt8 = 0

    override var classification: Classification { reading.classification }
    override var symptomsStatus: SymptomsStatus { reading.symptomsStatus }
    override var numberOfVoltageMeasurements: Int { reading.numberOfVoltageMeasurements }
    override var averageHeartRate: HKQuantity? { reading.averageHeartRate }
    override var samplingFrequency: HKQuantity? { reading.samplingFrequency }

    private var reading: Reading {
        guard let statement = objc_getAssociatedObject(self, &Self.readingKey) as? Statement else {
            preconditionFailure("A stored ECG states its reading when it is built")
        }
        return statement.reading
    }

    /// Attaches the reading every overridden property answers from.
    func state(_ reading: Reading) {
        objc_setAssociatedObject(self, &Self.readingKey, Statement(reading), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}


/// TEST-ONLY. Builds HealthKit samples the way the store hands them back: with a chosen UUID, an
/// attributable `HKSourceRevision`, and (for the series classes HealthKit offers no synthetic
/// initializer for) chosen dates, device and metadata. The content corpus also restates facts
/// HealthKit refuses when it creates a sample, and states ECG readings and voltages.
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

    /// `sample` carrying exactly `metadata`, written past HealthKit's initializer, which raises an Objective-C exception
    /// for a value it refuses (a half sync pair, a negative or textual sync version) instead of returning one.
    static func withMetadata<Sample: HKSample>(_ sample: Sample, _ metadata: [String: Any]) throws -> Sample {
        try write(metadata as NSDictionary, to: "metadata", of: sample)
        guard (sample.metadata ?? [:]).keys.sorted() == metadata.keys.sorted() else {
            throw FixtureError.keyNotHonored(key: "metadata", class: String(describing: type(of: sample)))
        }
        return sample
    }

    /// A bare instance of a sample class without a public initializer, carrying exactly `shape`.
    static func seriesSample<Sample: HKSample>(_ type: Sample.Type, sampleType: HKSampleType, shape: SeriesShape) throws -> Sample {
        let object = try allocate(type)
        try write(sampleType, to: "sampleType", of: object)
        let sample = try restated(unsafeDowncast(object, to: type), shape: shape)
        guard sample.sampleType == sampleType else {
            throw FixtureError.keyNotHonored(key: "sampleType", class: String(describing: type))
        }
        return sample
    }

    /// `sample` carrying exactly `shape`'s facts in place of the ones its initializer stated.
    ///
    /// HealthKit validates a sample only when it creates one, so a fact it refuses there (a reversed interval,
    /// a metadata value of the wrong type, an instant after 4000) can be stated only afterwards, as here.
    static func restated<Sample: HKSample>(_ sample: Sample, shape: SeriesShape) throws -> Sample {
        try write(NSNumber(value: shape.start.timeIntervalSinceReferenceDate), to: "startTimestamp", of: sample)
        try write(NSNumber(value: shape.end.timeIntervalSinceReferenceDate), to: "endTimestamp", of: sample)
        try write(shape.device, to: "device", of: sample)
        try write(shape.metadata, to: "metadata", of: sample)
        let stored = try stored(sample, uuid: shape.uuid, writer: shape.writer)
        let name = String(describing: type(of: sample))
        guard stored.startDate == shape.start, stored.endDate == shape.end else {
            throw FixtureError.keyNotHonored(key: "startTimestamp/endTimestamp", class: name)
        }
        guard stored.device == shape.device, (stored.metadata ?? [:]).keys.sorted() == (shape.metadata ?? [:]).keys.sorted() else {
            throw FixtureError.keyNotHonored(key: "device/metadata", class: name)
        }
        return stored
    }

    /// An ECG carrying exactly `shape` and stating `reading` as HealthKit would report it.
    static func electrocardiogram(shape: SeriesShape, reading: StoredElectrocardiogram.Reading) throws -> HKElectrocardiogram {
        let ecg = try seriesSample(StoredElectrocardiogram.self, sampleType: HKObjectType.electrocardiogramType(), shape: shape)
        ecg.state(reading)
        return ecg
    }

    /// One voltage of an ECG's lead, or a measurement that states no lead voltage at all.
    static func voltageMeasurement(offset: TimeInterval, millivolts: Double?) throws -> HKElectrocardiogram.VoltageMeasurement {
        let object = try allocate(HKElectrocardiogram.VoltageMeasurement.self)
        try write(NSNumber(value: offset), to: "timeSinceSampleStart", of: object)
        try write(millivolts.map { HKQuantity(unit: .voltUnit(with: .milli), doubleValue: $0) }, to: "leadIVoltage", of: object)
        let measurement = unsafeDowncast(object, to: HKElectrocardiogram.VoltageMeasurement.self)
        guard measurement.timeSinceSampleStart.bitPattern == offset.bitPattern,
              (measurement.quantity(for: .appleWatchSimilarToLeadI) == nil) == (millivolts == nil) else {
            throw FixtureError.keyNotHonored(key: "timeSinceSampleStart/leadIVoltage", class: "HKElectrocardiogram.VoltageMeasurement")
        }
        return measurement
    }

    /// An `HKElectrocardiogram` reading `shape`'s facts, its classification, symptoms status and average heart rate.
    /// Its voltages are HealthKit's private storage and stay unset, so it reports no measurement count and no sampling
    /// frequency. HealthKit keeps the classification under a private numbering: `reading` names that number and the
    /// public classification it must read back as, and the fixture fails unless every value reads back.
    static func electrocardiogram(
        shape: SeriesShape,
        reading: (privateClassification: Int, classification: HKElectrocardiogram.Classification),
        symptomsStatus: HKElectrocardiogram.SymptomsStatus,
        averageHeartRate: HKQuantity
    ) throws -> HKElectrocardiogram {
        let ecg = try seriesSample(HKElectrocardiogram.self, sampleType: HKObjectType.electrocardiogramType(), shape: shape)
        try write(NSNumber(value: reading.privateClassification), to: "privateClassification", of: ecg)
        try write(NSNumber(value: symptomsStatus.rawValue), to: "symptomsStatus", of: ecg)
        try write(averageHeartRate, to: "averageHeartRate", of: ecg)
        guard ecg.classification == reading.classification,
              ecg.symptomsStatus == symptomsStatus,
              ecg.averageHeartRate == averageHeartRate else {
            throw FixtureError.keyNotHonored(key: "privateClassification/symptomsStatus/averageHeartRate", class: String(describing: HKElectrocardiogram.self))
        }
        return ecg
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

    /// A bare instance of `type`, none of whose initializers ran.
    static func allocate(_ type: AnyClass) throws -> NSObject {
        guard let object = class_createInstance(type, 0) as? NSObject else {
            throw FixtureError.classNotConstructible(String(describing: type))
        }
        return object
    }

    /// Writes one private ivar through key-value coding, failing when the class no longer has it.
    static func write(_ value: Any?, to key: String, of object: NSObject) throws {
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

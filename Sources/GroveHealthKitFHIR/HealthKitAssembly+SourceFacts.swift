//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreFoundation
import Foundation
import GroveFHIRContract
import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    /// What a sample says about its origin, resolved once under the exporter's policies: the hardware it was measured on,
    /// who wrote it, and which clear identifiers travel.
    struct SourceFacts {
        let recordingDevice: RecordingDevice?
        let writer: ExchangeWriterDraft?
        let sourceRevision: Extension?
        let nativeIdentifiers: [Identifier]
        let writerRecord: ExchangeOutputDraft.WriterRecord?
        let wasUserEntered: Bool

        /// The facts of `sample`, whose metadata `metadata` bridged once, under what the policies answered for it. `outputs`
        /// are the record's: only an Observation output takes the sample's device metadata keys.
        init(
            _ sample: HKSample,
            metadata: HealthKitSampleMetadata,
            outputs: [ExchangeOutputDraft],
            policies: HealthKitFHIRExporter.ResolvedPolicies,
            options: HealthKitFHIRExporter.Options
        ) throws {
            let revision = sample.sourceRevision
            self.recordingDevice = sample.device.map { healthKitDevice in
                var device = RecordingDevice(healthKitDevice)
                // A record without an Observation output represents no metadata key (healthkit mapping.md, Withheld metadata).
                if outputs.contains(where: \.isObservation) {
                    device.fill(from: metadata)
                }
                device.identifyUnit(token: policies.unitToken, writer: revision.source)
                return device
            }
            self.writer = try Self.writer(revision, classification: policies.writer)
            self.sourceRevision = self.writer == nil ? Self.sourceRevision(revision) : nil
            self.nativeIdentifiers = [options.nativeIdentifier.identifier(for: sample.uuid.uuidString.lowercased())].compactMap(\.self)
            self.writerRecord = try Self.writerRecord(metadata: metadata.values, writerApplication: revision.source.bundleIdentifier)
            self.wasUserEntered = metadata.wasUserEntered
        }
    }
}


// MARK: - Recording device

@available(iOS 18, macOS 15, watchOS 11, *)
extension RecordingDevice {
    /// The hardware `device` names, with every fact it states.
    fileprivate init(_ device: HKDevice) {
        self.init()
        name = device.name?.nonBlank
        manufacturer = device.manufacturer?.nonBlank
        model = device.model?.nonBlank
        hardwareVersion = device.hardwareVersion?.nonBlank
        firmwareVersion = device.firmwareVersion?.nonBlank
        softwareVersion = device.softwareVersion?.nonBlank
        localIdentifier = device.localIdentifier?.nonBlank
        udiDeviceIdentifier = device.udiDeviceIdentifier?.nonBlank
    }

    /// Fills what `HKDevice` left absent from the sample's device metadata keys: an `HKDevice` property wins, and the serial
    /// number and the UDI production identifier come only from their keys. A value that is no text states nothing.
    fileprivate mutating func fill(from metadata: HealthKitSampleMetadata) {
        func stated(_ key: String) -> String? {
            (metadata.values[key] as? String)?.nonBlank
        }
        name = name ?? stated(HKMetadataKeyDeviceName)
        manufacturer = manufacturer ?? stated(HKMetadataKeyDeviceManufacturerName)
        udiDeviceIdentifier = udiDeviceIdentifier ?? stated(HKMetadataKeyUDIDeviceIdentifier)
        udiProductionIdentifier = stated(HKMetadataKeyUDIProductionIdentifier)
        serialNumber = stated(HKMetadataKeyDeviceSerialNumber)
    }

    /// States `token` as the unit `writer` assigned it: without a writer's bundle identifier the record names hardware, not
    /// a unit.
    fileprivate mutating func identifyUnit(token: String?, writer: HKSource) {
        tokenScope = writer.bundleIdentifier.nonBlank
        stableUnitToken = tokenScope == nil ? nil : token
    }

    /// The fact the device states in the element the guide gives the device metadata key `key`, or `nil` for any other key.
    func statedFact(forMetadataKey key: String) -> String? {
        switch key {
        case HKMetadataKeyDeviceSerialNumber: serialNumber
        case HKMetadataKeyDeviceName: name
        case HKMetadataKeyDeviceManufacturerName: manufacturer
        case HKMetadataKeyUDIDeviceIdentifier: udiDeviceIdentifier
        case HKMetadataKeyUDIProductionIdentifier: udiProductionIdentifier
        default: nil
        }
    }
}


// MARK: - Writer

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    private static func writer(
        _ revision: HKSourceRevision,
        classification: HealthKitFHIRExporter.WriterPolicy.Classification
    ) throws -> ExchangeWriterDraft? {
        switch classification {
        case .omit:
            return nil
        case .application:
            guard let name = revision.source.name.nonBlank,
                  let bundleIdentifier = revision.source.bundleIdentifier.nonBlank else {
                return nil
            }
            let version = revision.version?.nonBlank
            do {
                return ExchangeWriterDraft(
                    application: try ApplicationDevice(name: name, bundleIdentifier: bundleIdentifier, version: "unknown", build: version),
                    host: try HostDevice(
                        operatingSystemVersion: operatingSystemVersion(revision.operatingSystemVersion),
                        productType: revision.productType?.nonBlank
                    ),
                    statesVersion: false
                )
            } catch {
                throw HealthKitConversionError.sourceApplicationInvalid
            }
        }
    }

    private static func operatingSystemVersion(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}


// MARK: - Writer record

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    /// Apple's paired sync metadata, validated independently of source attribution. A valid pair
    /// without an attributable writer stays omitted rather than being assigned to an invented writer.
    static func writerRecord(metadata: [String: Any], writerApplication: String) throws -> ExchangeOutputDraft.WriterRecord? {
        let identifierValue = metadata[HKMetadataKeySyncIdentifier]
        let versionValue = metadata[HKMetadataKeySyncVersion]
        guard identifierValue != nil || versionValue != nil else {
            return nil
        }
        guard let syncIdentifier = identifierValue as? String, !syncIdentifier.isEmpty else {
            throw HealthKitConversionError.ValueFailure.invalidMetadataValue(.syncIdentifier)
        }
        guard let versionValue else {
            throw HealthKitConversionError.ValueFailure.invalidMetadataValue(.syncVersion)
        }
        let version = try canonicalSyncVersion(versionValue)
        guard !writerApplication.isEmpty else {
            return nil
        }
        return ExchangeOutputDraft.WriterRecord(writerApplication: writerApplication, syncIdentifier: syncIdentifier, version: version)
    }

    private static func canonicalSyncVersion(_ value: Any) throws -> String {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              var decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN,
              decimal >= 0 else {
            throw HealthKitConversionError.ValueFailure.invalidMetadataValue(.syncVersion)
        }
        var integral = Decimal()
        NSDecimalRound(&integral, &decimal, 0, .down)
        guard integral == decimal else {
            throw HealthKitConversionError.ValueFailure.invalidMetadataValue(.syncVersion)
        }
        return NSDecimalString(&integral, Locale(identifier: "en_US_POSIX"))
    }
}

#endif

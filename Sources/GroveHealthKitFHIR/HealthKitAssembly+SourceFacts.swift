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
    /// What a sample says about its origin, resolved once under the exporter's policies: the physical
    /// unit it was measured on, who wrote it, which clear identifiers travel, and what is withheld.
    struct SourceFacts {
        let recordingDevice: ExchangeRecordingDeviceDraft?
        let writer: ExchangeWriterDraft?
        let nativeIdentifiers: [Identifier]
        let writerRecord: ExchangeOutputDraft.WriterRecord?
        let wasUserEntered: Bool
        /// Each one registered `mobile-omission` rule. An omission a policy chose is not a warning.
        let warnings: [ProducerDiagnostic]

        /// The facts of `sample`, whose metadata `metadata` bridged once, under what the policies answered for it.
        init(
            _ sample: HKSample,
            metadata: HealthKitSampleMetadata,
            policies: HealthKitFHIRExporter.ResolvedPolicies,
            options: HealthKitFHIRExporter.Options
        ) throws {
            let revision = sample.sourceRevision
            var warnings: [ProducerDiagnostic] = []
            var recordingDevice: ExchangeRecordingDeviceDraft?
            if let healthKitDevice = sample.device {
                if let recorder = policies.recordingDevice {
                    recordingDevice = Self.recordingDevice(recorder, healthKitDevice: healthKitDevice, udi: options.udi)
                } else if options.recordingDevice.reportsDeclinedDevices {
                    // Model and version facts cannot identify a physical unit, so the shared recording
                    // Device is omitted rather than merged, and the omission is reported.
                    warnings.append(ExchangeGraphRule.mobileOmissionRecordingDevice.diagnostic)
                }
            }
            self.recordingDevice = recordingDevice
            self.writer = try Self.writer(revision, classification: policies.writer)
            self.nativeIdentifiers = [options.nativeIdentifier.identifier(for: sample.uuid.uuidString.lowercased())].compactMap(\.self)
            self.writerRecord = try Self.writerRecord(metadata: metadata.values, writerApplication: revision.source.bundleIdentifier)
            self.wasUserEntered = metadata.wasUserEntered
            if !metadata.withheldKeys.isEmpty {
                warnings.append(ExchangeGraphRule.mobileOmissionUnmodeledMetadata.diagnostic)
            }
            self.warnings = warnings
        }
    }
}


// MARK: - Recording device

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    /// The resolved physical unit with the facts its `HKDevice` states about it.
    private static func recordingDevice(
        _ recorder: RecordingDevice,
        healthKitDevice: HKDevice,
        udi: HealthKitFHIRExporter.Disclosure
    ) -> ExchangeRecordingDeviceDraft {
        var device = recordingDevice(
            name: recorder.name ?? healthKitDevice.name?.nonBlank,
            manufacturer: recorder.manufacturer ?? healthKitDevice.manufacturer?.nonBlank,
            modelNumber: recorder.modelNumber ?? healthKitDevice.model?.nonBlank
        )
        var versions: [DeviceVersion] = []
        versions.appendVersion(healthKitDevice.hardwareVersion, code: "531974", display: "MDC_ID_PROD_SPEC_HW")
        versions.appendVersion(healthKitDevice.firmwareVersion, code: "531976", display: "MDC_ID_PROD_SPEC_FW")
        versions.appendVersion(healthKitDevice.softwareVersion, code: "531975", display: "MDC_ID_PROD_SPEC_SW")
        device.version = versions.isEmpty ? nil : versions
        if udi == .authorized, let udi = healthKitDevice.udiDeviceIdentifier?.nonBlank {
            device.udiCarrier = [DeviceUdiCarrier(deviceIdentifier: udi.asFHIRStringPrimitive())]
        }
        return ExchangeRecordingDeviceDraft(device: recorder, resource: device)
    }

    private static func recordingDevice(name: String?, manufacturer: String?, modelNumber: String?) -> Device {
        var device = Device()
        device.meta = Meta(profile: [Profile.groveRecordingDevice])
        device.status = FHIRPrimitive(.active)
        if let name {
            device.deviceName = [DeviceDeviceName(name: name.asFHIRStringPrimitive(), type: FHIRPrimitive(.userFriendlyName))]
        }
        device.manufacturer = manufacturer?.asFHIRStringPrimitive()
        device.modelNumber = modelNumber?.asFHIRStringPrimitive()
        return device
    }
}


// MARK: - Writer

@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly.SourceFacts {
    private static func writer(_ revision: HKSourceRevision, classification: HealthKitWriter) throws -> ExchangeWriterDraft? {
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
                    application: try ApplicationDevice(name: name, bundleIdentifier: bundleIdentifier, version: version ?? "unknown"),
                    host: try HostDevice(
                        operatingSystemVersion: operatingSystemVersion(revision.operatingSystemVersion),
                        modelNumber: revision.productType?.nonBlank
                    ),
                    statesVersion: version != nil
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
            throw HealthKitValueFailure.invalidMetadataValue(.syncIdentifier)
        }
        guard let versionValue else {
            throw HealthKitValueFailure.invalidMetadataValue(.syncVersion)
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
            throw HealthKitValueFailure.invalidMetadataValue(.syncVersion)
        }
        var integral = Decimal()
        NSDecimalRound(&integral, &decimal, 0, .down)
        guard integral == decimal else {
            throw HealthKitValueFailure.invalidMetadataValue(.syncVersion)
        }
        return NSDecimalString(&integral, Locale(identifier: "en_US_POSIX"))
    }
}


extension Array where Element == DeviceVersion {
    fileprivate mutating func appendVersion(_ value: String?, code: String, display: String) {
        guard let value = value?.nonBlank else {
            return
        }
        let type = Coding(code: code.asFHIRStringPrimitive(), display: display.asFHIRStringPrimitive(), system: Canonicals.mdc)
        append(DeviceVersion(type: CodeableConcept(coding: [type]), value: value.asFHIRStringPrimitive()))
    }
}


extension String {
    /// The string, or `nil` when it is empty or holds nothing but whitespace.
    var nonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

#endif

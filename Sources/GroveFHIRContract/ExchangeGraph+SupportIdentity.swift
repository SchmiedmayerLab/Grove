//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


extension ExchangeGraph {
    /// Every supporting resource lies in a record unit: the directed closure of the lifecycle Provenances and their
    /// targets, so a node that only points at a record, as an orphaned application Device points at its host, is not in one.
    static func validateSupportingConnectivity(
        kind: Kind,
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        let units: RecordUnits
        do {
            units = try RecordUnits(entries: entries, document: document)
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        var starts: [String] = []
        for entry in entries {
            guard case .provenance(let provenance)? = entry.resource, let fullURL = entry.fullUrl?.value?.url.absoluteString else {
                continue
            }
            starts.append(fullURL)
            starts += provenance.target.compactMap { $0.reference?.value?.string }
        }
        let connected = units.unit(from: starts)
        let supportingTypes = kind == .active ? ExchangeContract.activeSupportingResourceTypes : [ResourceType.device.rawValue]
        let isDisconnected = entries.contains { entry in
            guard let resource = entry.resource, let fullURL = entry.fullUrl?.value?.url.absoluteString else {
                return false
            }
            return supportingTypes.contains(resource.resourceType) && !connected.contains(fullURL)
        }
        guard !isDisconnected else {
            throw .ruleViolation(.mobileSupportConnected)
        }
    }

    static func validateAdapterOnlyOutputProfile(
        _ resource: ResourceProxy,
        entryIndex: Int,
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        guard let expected = ProfileClaims.adapterOnlyOutputProfiles[resource.resourceType],
              let expectedProfile = expected.value?.url.absoluteString else {
            return
        }
        do {
            let object = try document.resourceObject(at: entryIndex) as? [String: Any]
            let meta = object?["meta"] as? [String: Any]
            let profiles = meta?["profile"] as? [String]
            guard profiles == [expectedProfile] else {
                throw ExchangeGraphError.ruleViolation(.mobileOutputAdapterOnlyProfile)
            }
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .ruleViolation(.mobileOutputAdapterOnlyProfile)
        }
    }

    static func validateDeviceIdentity(
        _ device: Device,
        entryKey: RoledIdentifier,
        identifiers: [RoledIdentifier]
    ) throws(ExchangeGraphError) {
        let profiles = [
            Profile.groveApplicationDevice,
            HealthKitContract.applicationDeviceProfile,
            Profile.groveHostDevice,
            Profile.groveRecordingDevice
        ].filter { device.meta?.profile?.contains($0) == true }
        let snapshots = identifiers.filter { $0.role == .deviceSnapshot }
        guard profiles.count == 1,
              snapshots.count == 1,
              snapshots[0] == entryKey,
              entryKey.role == .deviceSnapshot,
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(entryKey.identifier.value) else {
            throw .ruleViolation(.mobileDeviceRecordingDeviceDualIdentity)
        }
        if profiles[0] == HealthKitContract.applicationDeviceProfile {
            let bundleIdentifiers = device.identifier?.filter { identifier in
                let codings = identifier.type?.coding?.filter {
                    $0.system == HealthKitContract.appleBundleIdentifierTypeSystem
                } ?? []
                return codings.count == 1
                    && codings[0].code?.value?.string
                        == HealthKitContract.appleBundleIdentifierTypeCode
            } ?? []
            guard device.identifier?.count == 2,
                  identifiers.count == 1,
                  bundleIdentifiers.count == 1,
                  bundleIdentifiers[0].system == HealthKitContract.appleBundleIdentifierSystem,
                  bundleIdentifiers[0].value?.value?.string.isEmpty == false else {
                throw .ruleViolation(.mobileDeviceRecordingDeviceDualIdentity)
            }
        } else if profiles[0] == Profile.groveRecordingDevice {
            // The physical-unit identity is optional, and clear source identifiers may ride beside the typed ones.
            guard identifiers.filter({ $0.role == .recordingDevice }).count <= 1,
                  identifiers.allSatisfy({ $0.role == .deviceSnapshot || $0.role == .recordingDevice }) else {
                throw .ruleViolation(.mobileDeviceRecordingDeviceDualIdentity)
            }
        } else if profiles[0] == Profile.groveHostDevice {
            guard device.identifier?.count == 1, identifiers.count == 1 else {
                throw .ruleViolation(.mobileDeviceRecordingDeviceDualIdentity)
            }
        }
    }

    static func isActiveOutput(_ resource: ResourceProxy) -> Bool {
        switch resource {
        case .observation, .documentReference, .visionPrescription,
             .medicationAdministration, .medicationStatement, .specimen:
            true
        default:
            false
        }
    }
}

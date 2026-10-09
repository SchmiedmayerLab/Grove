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
    static func validateSupportingConnectivity(
        entries: [BundleEntry],
        document: ValidationDocument
    ) throws(ExchangeGraphError) {
        let resourcePairs: [(String, (resource: ResourceProxy, index: Int))] = entries.enumerated().compactMap { index, entry in
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString,
                  let resource = entry.resource else {
                return nil
            }
            return (fullURL, (resource, index))
        }
        let entriesByFullURL = [String: (resource: ResourceProxy, index: Int)](
            uniqueKeysWithValues: resourcePairs
        )
        let resourcesByFullURL = entriesByFullURL.mapValues(\.resource)
        var adjacency = [String: Set<String>](
            uniqueKeysWithValues: resourcesByFullURL.keys.map { ($0, Set<String>()) }
        )
        do {
            for (fullURL, entry) in entriesByFullURL {
                for object in try document.resourceObjects(at: entry.index) {
                    guard let reference = object["reference"] as? String, resourcesByFullURL[reference] != nil else {
                        continue
                    }
                    adjacency[fullURL, default: []].insert(reference)
                    adjacency[reference, default: []].insert(fullURL)
                }
            }
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        var reachable = Set(resourcesByFullURL.compactMap { fullURL, resource in
            isActiveOutput(resource) || resource.resourceType == ExchangeContract.activeLifecycleResourceType
                ? fullURL
                : nil
        })
        var pending = Array(reachable)
        while let current = pending.popLast() {
            for neighbor in adjacency[current, default: []] where reachable.insert(neighbor).inserted {
                pending.append(neighbor)
            }
        }
        let disconnected = resourcesByFullURL.contains { fullURL, resource in
            ExchangeContract.activeSupportingResourceTypes.contains(resource.resourceType)
                && !reachable.contains(fullURL)
        }
        guard !disconnected else {
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
            guard device.identifier?.count == 2,
                  identifiers.count == 2,
                  identifiers.filter({ $0.role == .recordingDevice }).count == 1 else {
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

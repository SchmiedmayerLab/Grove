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
        entries: [BundleEntry]
    ) throws(ExchangeGraphError) {
        let resourcePairs: [(String, ResourceProxy)] = entries.compactMap { entry in
            guard let fullURL = entry.fullUrl?.value?.url.absoluteString,
                  let resource = entry.resource else {
                return nil
            }
            return (fullURL, resource)
        }
        let resourcesByFullURL = [String: ResourceProxy](
            uniqueKeysWithValues: resourcePairs
        )
        var adjacency = [String: Set<String>](
            uniqueKeysWithValues: resourcesByFullURL.keys.map { ($0, Set<String>()) }
        )
        do {
            for (fullURL, resource) in resourcesByFullURL {
                let data = try JSONEncoder().encode(resource)
                let object = try JSONSerialization.jsonObject(with: data)
                var references: Set<String> = []
                collectLiteralReferences(in: object, into: &references)
                for reference in references where resourcesByFullURL[reference] != nil {
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
            throw .ruleViolation(.supportConnected)
        }
    }

    static func collectLiteralReferences(
        in value: Any,
        into references: inout Set<String>
    ) {
        if let object = value as? [String: Any] {
            if let reference = object["reference"] as? String {
                references.insert(reference)
            }
            for child in object.values {
                collectLiteralReferences(in: child, into: &references)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectLiteralReferences(in: child, into: &references)
            }
        }
    }

    static func validateAdapterOnlyOutputProfile(
        _ resource: ResourceProxy
    ) throws(ExchangeGraphError) {
        guard let expected = ProfileClaims.adapterOnlyOutputProfiles[resource.resourceType],
              let expectedProfile = expected.value?.url.absoluteString else {
            return
        }
        do {
            let data = try JSONEncoder().encode(resource)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let meta = object?["meta"] as? [String: Any]
            let profiles = meta?["profile"] as? [String]
            guard profiles == [expectedProfile] else {
                throw ExchangeGraphError.ruleViolation(.adapterOnlyProfile)
            }
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .ruleViolation(.adapterOnlyProfile)
        }
    }

    static func validateDeviceIdentity(
        _ device: Device,
        entryKey: BusinessIdentifier,
        identifiers: [BusinessIdentifier]
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
              ExchangeIdentity.isCanonicalOpaqueIdentifierValue(entryKey.value) else {
            throw .ruleViolation(.recordingDeviceDualIdentity)
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
                throw .ruleViolation(.recordingDeviceDualIdentity)
            }
        } else if profiles[0] == Profile.groveRecordingDevice {
            guard device.identifier?.count == 2,
                  identifiers.count == 2,
                  identifiers.filter({ $0.role == .recordingDevice }).count == 1 else {
                throw .ruleViolation(.recordingDeviceDualIdentity)
            }
        } else if profiles[0] == Profile.groveHostDevice {
            guard device.identifier?.count == 1, identifiers.count == 1 else {
                throw .ruleViolation(.recordingDeviceDualIdentity)
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

    static func entryKey(_ entry: BundleEntry) throws -> BusinessIdentifier? {
        guard let extensionValue = entry.extension?.first(where: { $0.url == Canonicals.entryNodeKey }),
              case .identifier(let identifier)? = extensionValue.value else {
            return nil
        }
        return try BusinessIdentifier(identifier)
    }
}

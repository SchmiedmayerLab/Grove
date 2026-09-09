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
    static func validateSerializedEntryPolicy(
        kind: ExchangeGraphKind,
        data: Data
    ) throws(ExchangeGraphError) {
        let root = try serializedBundleObject(data)
        let activeTypes = ExchangeContract.activeOutputResourceTypes
            .union(ExchangeContract.activeSupportingResourceTypes)
            .union([ExchangeContract.activeLifecycleResourceType])
        for entry in root["entry"] as? [[String: Any]] ?? [] {
            try validateSerializedEntry(entry, kind: kind, activeTypes: activeTypes)
        }
    }

    private static func serializedBundleObject(_ data: Data) throws(ExchangeGraphError) -> [String: Any] {
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ExchangeGraphError.invalidEntries("Bundle is not a JSON object")
            }
            root = object
        } catch let error as ExchangeGraphError {
            throw error
        } catch {
            throw .invalidEntries(String(reflecting: type(of: error)))
        }
        return root
    }

    private static func validateSerializedEntry(
        _ entry: [String: Any],
        kind: ExchangeGraphKind,
        activeTypes: Set<String>
    ) throws(ExchangeGraphError) {
        guard let resource = entry["resource"] as? [String: Any],
              let resourceType = resource["resourceType"] as? String else {
            throw .invalidEntries("Bundle entry has no resourceType")
        }
        switch kind {
        case .active:
            try validateSerializedActiveResource(resource, resourceType: resourceType, activeTypes: activeTypes)
        case .retraction:
            try validateSerializedRetractionResource(resource, resourceType: resourceType)
        }
        guard resource["contained"] == nil,
              !containsContainedReference(resource) else {
            throw .ruleViolation(.containedResourceProhibited)
        }
    }

    private static func validateSerializedActiveResource(
        _ resource: [String: Any],
        resourceType: String,
        activeTypes: Set<String>
    ) throws(ExchangeGraphError) {
        guard activeTypes.contains(resourceType) else {
            throw .ruleViolation(.entryResourceType)
        }
        if let expectedProfile = ProfileClaims.adapterOnlyOutputProfiles[resourceType]
            .flatMap({ $0.value?.url.absoluteString }) {
            let profiles = (resource["meta"] as? [String: Any])?["profile"] as? [String]
            guard profiles == [expectedProfile] else {
                throw .ruleViolation(.adapterOnlyProfile)
            }
        }
    }

    private static func validateSerializedRetractionResource(
        _ resource: [String: Any],
        resourceType: String
    ) throws(ExchangeGraphError) {
        guard resourceType == ResourceType.provenance.rawValue
                || resourceType == ResourceType.device.rawValue else {
            throw .ruleViolation(.retractionNoClinicalCopy)
        }
        if resourceType == ResourceType.provenance.rawValue,
           let targets = resource["target"] as? [[String: Any]],
           targets.contains(where: { $0["reference"] != nil }) {
            throw .ruleViolation(.retractionLogicalTarget)
        }
    }

    static func containsContainedReference(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if let reference = object["reference"] as? String,
               reference.hasPrefix("#") {
                return true
            }
            return object.values.contains(where: containsContainedReference)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsContainedReference)
        }
        return false
    }
}

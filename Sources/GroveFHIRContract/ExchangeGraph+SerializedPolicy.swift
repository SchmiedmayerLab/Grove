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
        kind: Kind,
        json: Result<Any, any Error>
    ) throws(ExchangeGraphError) {
        let root = try serializedBundleObject(json)
        let activeTypes = ExchangeContract.activeOutputResourceTypes
            .union(ExchangeContract.activeSupportingResourceTypes)
            .union([ExchangeContract.activeLifecycleResourceType])
        let entries = root["entry"] as? [[String: Any]] ?? []
        for entry in entries {
            try validateSerializedEntry(entry, kind: kind, activeTypes: activeTypes)
        }
        // Checked before decoding: a re-typed output need not decode as its claimed resource.
        if kind == .active, !entries.isEmpty, !entries.contains(where: { entry in
            let resource = entry["resource"] as? [String: Any]
            return ExchangeContract.activeOutputResourceTypes.contains(resource?["resourceType"] as? String ?? "")
        }) {
            throw diagnostic(.mobileExchangeOutputRequired, location: "Bundle.entry")
        }
    }

    private static func serializedBundleObject(_ json: Result<Any, any Error>) throws(ExchangeGraphError) -> [String: Any] {
        let root: [String: Any]
        do {
            guard let object = try json.get() as? [String: Any] else {
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
        kind: Kind,
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
            throw .ruleViolation(.mobileExchangeContainedResourceProhibited)
        }
    }

    private static func validateSerializedActiveResource(
        _ resource: [String: Any],
        resourceType: String,
        activeTypes: Set<String>
    ) throws(ExchangeGraphError) {
        guard activeTypes.contains(resourceType) else {
            throw .ruleViolation(.mobileExchangeEntryResourceType)
        }
        if let expectedProfile = ProfileClaims.adapterOnlyOutputProfiles[resourceType]
            .flatMap({ $0.value?.url.absoluteString }) {
            let profiles = (resource["meta"] as? [String: Any])?["profile"] as? [String]
            guard profiles == [expectedProfile] else {
                throw .ruleViolation(.mobileOutputAdapterOnlyProfile)
            }
        }
    }

    private static func validateSerializedRetractionResource(
        _ resource: [String: Any],
        resourceType: String
    ) throws(ExchangeGraphError) {
        guard resourceType == ResourceType.provenance.rawValue
                || resourceType == ResourceType.device.rawValue else {
            throw .ruleViolation(.mobileRetractionNoClinicalCopy)
        }
        if resourceType == ResourceType.provenance.rawValue,
           let targets = resource["target"] as? [[String: Any]],
           targets.contains(where: { $0["reference"] != nil }) {
            throw .ruleViolation(.mobileRetractionLogicalTarget)
        }
    }

    static func containsContainedReference(_ value: Any) -> Bool {
        struct ContainedReference: Error {}
        do {
            try ExchangeIdentity.walkJSONObjects(value) { object throws(ContainedReference) in
                if refersToContainedResource(object) {
                    throw ContainedReference()
                }
            }
            return false
        } catch {
            return true
        }
    }

    /// Whether `object` is a Reference to a contained resource (`#id`).
    static func refersToContainedResource(_ object: [String: Any]) -> Bool {
        (object["reference"] as? String)?.hasPrefix("#") == true
    }
}

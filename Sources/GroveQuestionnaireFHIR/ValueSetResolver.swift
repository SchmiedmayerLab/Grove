//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


struct CodingIdentity: Equatable {
    // periphery:ignore - read by the synthesized Equatable; `codingKey` values are only ever compared
    let system: String?
    // periphery:ignore - read by the synthesized Equatable; `codingKey` values are only ever compared
    let code: String
}


struct QuantityIdentity: Equatable {
    let value: Decimal
    let system: String
    let code: String
}


struct ValueSetResolver {
    private let resources: [String: FHIRJSONObject]

    init(valueSets: [FHIRJSONObject]) {
        var resources: [String: FHIRJSONObject] = [:]
        for valueSet in valueSets where valueSet["resourceType"] as? String == "ValueSet" {
            guard let url = valueSet["url"] as? String else {
                continue
            }
            resources[url] = valueSet
            if let version = valueSet["version"] as? String {
                resources["\(url)|\(version)"] = valueSet
            }
        }
        self.resources = resources
    }

    // Tri-state: nil means deterministic expansion or input interpretation is unavailable.
    // swiftlint:disable:next discouraged_optional_boolean
    func contains(canonical: String, coding: Any) -> Bool? {
        guard let valueSet = resources[canonical],
              let coding = coding as? FHIRJSONObject,
              let code = coding["code"] as? String,
              !code.isEmpty else {
            return nil
        }
        let system = coding["system"] as? String
        let compose = valueSet["compose"] as? FHIRJSONObject
        for include in compose?["include"] as? [FHIRJSONObject] ?? [] {
            if include["filter"] != nil || include["valueSet"] != nil {
                return nil
            }
            guard include["system"] as? String == system else {
                continue
            }
            guard let concepts = include["concept"] as? [FHIRJSONObject] else {
                return nil
            }
            if concepts.contains(where: { $0["code"] as? String == code }) {
                return true
            }
        }
        let expansion = valueSet["expansion"] as? FHIRJSONObject
        if (expansion?["contains"] as? [FHIRJSONObject] ?? []).contains(where: {
            $0["system"] as? String == system && $0["code"] as? String == code
        }) {
            return true
        }
        return false
    }
}

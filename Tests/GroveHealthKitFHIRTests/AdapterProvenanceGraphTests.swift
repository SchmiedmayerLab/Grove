//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveFHIRContract
@testable import GroveHealthKitFHIR
import Testing


/// Re-validation reports what the pinned kit reports for a golden it was handed with one fault: the kit's results for
/// these vectors were computed by running `exchange_bundle_diagnostics` on the same edited JSON (ig-pin, read-only).
///
/// `mobile-exchange.adapter-provenance-graph` (spec F11): every adapter output must sit under its adapter's conversion
/// Provenance, which targets exactly the adapter's outputs of its source record; the kit decides this last, by claim.
@Suite
struct AdapterProvenanceGraphTests {
    /// One edited golden and what re-validating it reports.
    struct Vector: CustomTestStringConvertible, Sendable {
        let testDescription: String
        let golden: String
        /// `nil` when the edited graph is accepted.
        let expected: (code: String, location: String)?
        let edit: @Sendable (inout [String: Any]) throws -> Void

        init(
            _ testDescription: String,
            golden: String,
            expected: (code: String, location: String)?,
            edit: @escaping @Sendable (inout [String: Any]) throws -> Void
        ) {
            self.testDescription = testDescription
            self.golden = golden
            self.expected = expected
            self.edit = edit
        }
    }

    private static let provenanceProfiles = [
        "mobile": "https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-conversion-provenance",
        "sensorkit": "https://grovealliance.org/fhir/sensorkit/StructureDefinition/sensorkit-conversion-provenance",
        "providers": "https://grovealliance.org/fhir/providers/StructureDefinition/providers-conversion-provenance",
        "health-connect": "https://grovealliance.org/fhir/health-connect/StructureDefinition/health-connect-conversion-provenance"
    ]

    private static let graphRule = "mobile-exchange.adapter-provenance-graph"

    static let vectors: [Vector] = [
        // T1: HealthKit outputs under a source-neutral or another adapter's Provenance.
        governing("mobile", expected: (graphRule, "Bundle.entry")),
        governing("sensorkit", expected: (graphRule, "Bundle.entry")),
        governing("providers", expected: (graphRule, "Bundle.entry")),
        // T2: the moved graph rule does not pre-empt the Health Connect data-origin check.
        governing("health-connect", expected: ("health-connect-provenance.data-origin-agent", "Provenance.entity[0].agent")),
        // T3: a HealthKit Provenance that also targets a source-neutral output of its record.
        Vector("a target outside the adapter's outputs", golden: "heart-rate-minimal", expected: (graphRule, "Provenance.target")) { bundle in
            try appendOutput(to: &bundle, adapterClaimed: false)
        },
        Vector("a target outside the adapter's outputs, targeted first", golden: "heart-rate-minimal", expected: (graphRule, "Provenance.target")) { bundle in
            try appendOutput(to: &bundle, adapterClaimed: false, targetIndex: 0)
        },
        Vector("a second adapter output of the record, targeted", golden: "heart-rate-minimal", expected: nil) { bundle in
            try appendOutput(to: &bundle, adapterClaimed: true)
        },
        // T4: an entry that is no output claims an adapter output profile; the kit fails it without a rule.
        Vector("a Patient claiming an adapter output profile", golden: "bundled-patient-subject", expected: ("mobile-exchange.unclassified", "Bundle")) { bundle in
            try edit(&bundle, entry: 1) { entry in
                try edit(&entry, member: "resource") { resource in
                    resource["meta"] = ["profile": ["https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-observation"]]
                }
            }
        },
        // A Provenance claiming an adapter's conversion profile beside another; the kit fails it without a rule.
        Vector("a Provenance claiming two conversion profiles", golden: "heart-rate-minimal", expected: ("mobile-exchange.unclassified", "Bundle")) { bundle in
            try edit(&bundle, entry: 3) { entry in
                try edit(&entry, member: "resource") { resource in
                    let healthKit = "https://grovealliance.org/fhir/healthkit/StructureDefinition/healthkit-conversion-provenance"
                    resource["meta"] = ["profile": [healthKit, provenanceProfiles["mobile"] ?? ""]]
                }
            }
        }
    ] + dataOriginVectors

    /// `health-connect-provenance.data-origin-agent`, located where the kit finds each fault (profiles.py:663-707).
    static let dataOriginVectors: [Vector] = [
        dataOrigin("an author agent", golden: "writer-foreign-application", agents: nil, at: ".agent[0].who"),
        dataOrigin("an enterer under another system", agents: { _ in [enterer(system: "https://grovealliance.org/fhir/testing/identifiers/package")] }, at: ".agent[0].who.identifier"),
        dataOrigin("an enterer with a blank package name", agents: { _ in [enterer(value: "  ")] }, at: ".agent[0].who.identifier"),
        dataOrigin("an enterer and an author", agents: { converter in [enterer(), ["type": participant(["author"]), "who": ["reference": converter]]] }, at: ".agent"),
        dataOrigin("an agent typed enterer and author", agents: { _ in [enterer(typedAs: ["enterer", "author"])] }, at: ".agent[0].who"),
        dataOrigin("an agent typed enterer twice", agents: { _ in [enterer(typedAs: ["enterer", "enterer"])] }, at: ".agent[0].who"),
        dataOrigin("an enterer referencing a Device", agents: { converter in [["type": participant(["enterer"]), "who": ["reference": converter, "type": "Device"]]] }, at: ".agent[0].who"),
        // A complete data origin passes the rule; the HealthKit outputs then fail the graph rule.
        Vector("a complete data origin over HealthKit outputs", golden: "heart-rate-minimal", expected: (graphRule, "Bundle.entry")) { bundle in
            try governedByHealthConnect(&bundle) { _ in [enterer()] }
        }
    ]

    /// A participant type coded once per code, in order.
    private static func participant(_ codes: [String]) -> [String: Any] {
        ["coding": codes.map { ["system": "http://terminology.hl7.org/CodeSystem/provenance-participant-type", "code": $0] }]
    }

    private static func enterer(
        system: String = "https://grovealliance.org/fhir/health-connect/NamingSystem/android-package-name",
        value: String = "com.example.scale",
        typedAs codes: [String] = ["enterer"]
    ) -> [String: Any] {
        ["type": participant(codes), "who": ["type": "Device", "identifier": ["system": system, "value": value]]]
    }

    private static func dataOrigin(
        _ description: String,
        golden: String = "heart-rate-minimal",
        agents: (@Sendable (_ converter: String) -> [[String: Any]])?,
        at location: String
    ) -> Vector {
        let expected = ("health-connect-provenance.data-origin-agent", "Provenance.entity[0]" + location)
        return Vector("Health Connect Provenance with \(description)", golden: golden, expected: expected) { bundle in
            try governedByHealthConnect(&bundle, agents: agents)
        }
    }

    /// The graph's Provenance claiming Health Connect's conversion profile, its source entity naming the agents
    /// `agents` builds from the converter's resolving reference, when given.
    private static func governedByHealthConnect(
        _ bundle: inout [String: Any],
        agents: (@Sendable (_ converter: String) -> [[String: Any]])?
    ) throws {
        let entries = try #require(bundle["entry"] as? [[String: Any]])
        let index = try #require(entries.firstIndex { ($0["resource"] as? [String: Any])?["resourceType"] as? String == "Provenance" })
        try edit(&bundle, entry: index) { entry in
            try edit(&entry, member: "resource") { resource in
                resource["meta"] = ["profile": [provenanceProfiles["health-connect"] ?? ""]]
                guard let agents else {
                    return
                }
                let assembler = try #require((resource["agent"] as? [[String: Any]])?.first?["who"] as? [String: Any])
                let converter = try #require(assembler["reference"] as? String)
                try edit(&resource, member: "entity", index: 0) { $0["agent"] = agents(converter) }
            }
        }
    }

    /// heart-rate-minimal with its Provenance claiming `adapter`'s conversion profile instead of HealthKit's.
    private static func governing(_ adapter: String, expected: (code: String, location: String)) -> Vector {
        Vector("HealthKit outputs under the \(adapter) Provenance", golden: "heart-rate-minimal", expected: expected) { bundle in
            try edit(&bundle, entry: 3) { entry in
                try edit(&entry, member: "resource") { resource in
                    resource["meta"] = ["profile": [provenanceProfiles[adapter] ?? ""]]
                }
            }
        }
    }

    /// Adds a copy of entry 0 as a second output of the same record, under a new source-output identity and the
    /// fullUrl it keys, claiming the HealthKit adapter or only its source-neutral profile, and targets it at
    /// `targetIndex`, by default after the existing targets.
    private static func appendOutput(to bundle: inout [String: Any], adapterClaimed: Bool, targetIndex: Int? = nil) throws {
        var entries = try #require(bundle["entry"] as? [[String: Any]])
        var output = entries[0]
        let identity = try #require(entries[0]["extension"] as? [[String: Any]]).first?["valueIdentifier"] as? [String: Any]
        let system = try #require(identity?["system"] as? String)
        let value = "v0:test:1:" + String(repeating: "A", count: 43)
        let fullURL = try RoledIdentifier(identifier: BusinessIdentifier(system: IdentifierSystem(system), value: value), role: .sourceOutput).fullURLString
        output["fullUrl"] = fullURL
        try edit(&output, member: "extension", index: 0) { node in
            try edit(&node, member: "valueIdentifier") { $0["value"] = value }
        }
        try edit(&output, member: "resource") { resource in
            try edit(&resource, member: "identifier", index: 1) { $0["value"] = value }
            if !adapterClaimed {
                resource["meta"] = ["profile": ["https://grovealliance.org/fhir/mobile/StructureDefinition/grove-mobile-heart-rate"]]
                resource["extension"] = nil
            }
        }
        entries.append(output)
        try edit(&entries[3], member: "resource") { provenance in
            var targets = try #require(provenance["target"] as? [[String: Any]])
            targets.insert(["reference": fullURL], at: targetIndex ?? targets.count)
            provenance["target"] = targets
        }
        bundle["entry"] = entries
    }

    private static func edit(_ bundle: inout [String: Any], entry index: Int, _ change: (inout [String: Any]) throws -> Void) throws {
        try edit(&bundle, member: "entry", index: index, change)
    }

    private static func edit(_ object: inout [String: Any], member: String, _ change: (inout [String: Any]) throws -> Void) throws {
        var value = try #require(object[member] as? [String: Any])
        try change(&value)
        object[member] = value
    }

    private static func edit(_ object: inout [String: Any], member: String, index: Int, _ change: (inout [String: Any]) throws -> Void) throws {
        var array = try #require(object[member] as? [[String: Any]])
        try change(&array[index])
        object[member] = array
    }

    @Test(arguments: AdapterProvenanceGraphTests.vectors)
    func reportsWhatTheKitReports(_ vector: Vector) throws {
        var bundle = try #require(try JSONSerialization.jsonObject(with: GoldenStore.data(named: vector.golden)) as? [String: Any])
        try vector.edit(&bundle)
        let json = try JSONSerialization.data(withJSONObject: bundle, options: [.sortedKeys, .withoutEscapingSlashes])
        do {
            _ = try ExchangeGraph(validating: json, kind: .active)
            #expect(vector.expected == nil, "accepted, the kit reports \(String(describing: vector.expected))")
        } catch {
            let diagnostic = error.diagnostic
            #expect(vector.expected?.code == diagnostic.code && vector.expected?.location == diagnostic.location, "reported \(diagnostic.code) @ \(diagnostic.location)")
        }
    }
}

#endif

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract
import Testing


@Suite
struct ExchangeGraphSerializedInputTests {
    @Test("Serialized events reject ambiguous or malformed JSON before model decoding", arguments: [
        #"{"resourceType":"Bundle","resourceType":"Patient"}"#,
        #"{"resourceType":"Bundle","entry":[{"resource":{"id":"first","id":"second"}}]}"#,
        #"{"resourceType":"Bundle","resourceType":"Bundle"}"#,
        #"{"resourceType":"Bundle","unrecognized":{"secret":"first","secret":"second"}}"#,
        "\u{FEFF}{\"resourceType\":\"Bundle\"}",
        #"{"resourceType":"Bundle","unrecognized":1e9999}"#,
        #"{"resourceType":"Bundle"} trailing"#,
        "{\"nested\":" + String(repeating: "[", count: 513) + "0" + String(repeating: "]", count: 513) + "}"
    ], [ExchangeGraph.Kind.active, .retraction])
    func rejectsMalformedJSON(json: String, kind: ExchangeGraph.Kind) {
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(validating: Data(json.utf8), kind: kind)
        }
    }

    @Test("Serialized events reject invalid UTF-8 before model decoding", arguments: [
        ExchangeGraph.Kind.active, .retraction
    ])
    func rejectsInvalidUTF8(kind: ExchangeGraph.Kind) {
        let bytes = Data([0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(validating: bytes, kind: kind)
        }
    }

    @Test("Grove identifier namespaces are checked before URL normalization", arguments: [
        "https://study.example.org/identifiers/naïve",
        "https://study.example.org/identifiers/with space"
    ], [ExchangeGraph.Kind.active, .retraction])
    func rejectsRawInvalidIdentifierSystem(system: String, kind: ExchangeGraph.Kind) {
        // A nested logical reference, because checking only Bundle.identifier would miss the same ambiguity there.
        let identifier = #"""
        {"system":"\#(system)","value":"subject","type":{"coding":[{
          "system":"https://grovealliance.org/fhir/mobile/CodeSystem/grove-identifier-role",
          "code":"source-output"
        }]}}
        """#
        let resource = switch kind {
        case .active: #"{"resourceType":"Observation","subject":{"identifier":\#(identifier)}}"#
        case .retraction: #"{"resourceType":"Provenance","target":[{"identifier":\#(identifier)}]}"#
        }
        let json = #"{"resourceType":"Bundle","entry":[{"resource":\#(resource)}]}"#
        #expect(throws: ExchangeGraphError.ruleViolation(.mobileExchangeOpaqueResourceIdentity)) {
            try ExchangeGraph(validating: Data(json.utf8), kind: kind)
        }
    }
}

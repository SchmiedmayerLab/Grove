//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
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
        #"{"resourceType":"Bundle","\u0072esourceType":"Bundle"}"#,
        #"{"resourceType":"Bundle","unrecognized":{"secret":"first","secret":"second"}}"#,
        "\u{FEFF}{\"resourceType\":\"Bundle\"}",
        #"{"resourceType":"Bundle","unrecognized":1e9999}"#,
        #"{"resourceType":"Bundle"} trailing"#,
        "{\"nested\":" + String(repeating: "[", count: 513) + "0" + String(repeating: "]", count: 513) + "}"
    ], [ExchangeGraphKind.active, .retraction])
    func rejectsMalformedJSON(json: String, kind: ExchangeGraphKind) {
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(kind: kind, jsonData: Data(json.utf8))
        }
    }

    @Test("Serialized events reject invalid UTF-8 before model decoding", arguments: [
        ExchangeGraphKind.active, .retraction
    ])
    func rejectsInvalidUTF8(kind: ExchangeGraphKind) {
        let bytes = Data([0x7B, 0x22, 0x78, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D])
        #expect(throws: ExchangeGraphError.invalidEntries("Serialized event is not strict JSON")) {
            try ExchangeGraph(kind: kind, jsonData: bytes)
        }
    }

    @Test("Grove identifier namespaces are checked before URL normalization", arguments: [
        "https://study.example.org/identifiers/naïve",
        "https://study.example.org/identifiers/with space"
    ], [ExchangeGraphKind.active, .retraction])
    func rejectsRawInvalidIdentifierSystem(system: String, kind: ExchangeGraphKind) {
        // Deliberately place the identifier inside a nested logical reference. Checking only
        // Bundle.identifier would miss the same ambiguity in reference/source identities.
        let json = #"""
        {"resourceType":"Bundle","entry":[{"resource":{"resourceType":"Observation","subject":{
          "identifier":{"system":"\#(system)","value":"subject","type":{"coding":[{
            "system":"https://grovealliance.org/fhir/mobile/CodeSystem/grove-identifier-role",
            "code":"source-output"
          }]}}
        }}}]}
        """#
        #expect(throws: ExchangeGraphError.ruleViolation(.identitySystemRole)) {
            try ExchangeGraph(kind: kind, jsonData: Data(json.utf8))
        }
    }
}

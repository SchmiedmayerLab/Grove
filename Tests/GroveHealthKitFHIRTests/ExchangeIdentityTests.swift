//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFHIRContract
import Testing


@Suite
struct GroveFHIRExchangeIdentityTests {
    @Test(
        "Matches the frozen composed UUIDv5 vectors",
        arguments: [
            (
                "https://study.example.org/fhir/identifiers/mobile-observation",
                "heart-rate-20260820-001",
                "https://study.example.org/fhir/identifiers/mobile-observation|heart-rate-20260820-001",
                "urn:uuid:72a64652-0bad-517d-8a36-39e3b6adccac"
            ),
            (
                "https://\u{4f8b}.example/\u{8b58}\u{5225}\u{5b50}",
                "caf\u{e9}-\u{6771}\u{4eac}",
                "https://\u{4f8b}.example/\u{8b58}\u{5225}\u{5b50}|caf\u{e9}-\u{6771}\u{4eac}",
                "urn:uuid:31acad95-5e9a-5b0f-b5b7-4f4627825b6b"
            ),
            // A composed identifier value carries vertical bars of its own; only the system may not.
            (
                "https://grovealliance.org/fhir/mobile/NamingSystem/grove-writer-record-id",
                "v1:com.withings.wiscale2|17348211",
                "https://grovealliance.org/fhir/mobile/NamingSystem/grove-writer-record-id"
                    + "|v1:com.withings.wiscale2|17348211",
                "urn:uuid:68db0fd4-0146-59c9-86cf-934f00881095"
            )
        ]
    )
    func frozenVector(system: String, value: String, input: String, fullURL: String) throws {
        #expect(ExchangeIdentity.canonicalName(system: system, value: value) == input)
        #expect(try ExchangeIdentity.fullURL(system: system, value: value) == fullURL)
    }
}

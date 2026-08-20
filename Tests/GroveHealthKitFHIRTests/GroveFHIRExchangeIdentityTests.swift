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
        "Matches the frozen RFC 8785/JCS UUIDv5 vectors",
        arguments: [
            (
                "https://study.example.org/fhir/identifiers/mobile-observation",
                "heart-rate-20260820-001",
                #"["https://study.example.org/fhir/identifiers/mobile-observation","heart-rate-20260820-001"]"#,
                "urn:uuid:cd27941b-2a75-5f7a-bd25-71e9480eac24"
            ),
            (
                "https://example.org/\"quoted\"",
                "back\\slash",
                #"["https://example.org/\"quoted\"","back\\slash"]"#,
                "urn:uuid:fe6c20ac-f147-5322-8804-c09d5c0f62d6"
            ),
            (
                "https://example.org/control",
                "line\nfeed\u{0001}",
                #"["https://example.org/control","line\nfeed\u0001"]"#,
                "urn:uuid:9a1a6b19-a138-5fdf-8954-68a3da142c64"
            ),
            (
                "https://例.example/識別子",
                "café-東京",
                #"["https://例.example/識別子","café-東京"]"#,
                "urn:uuid:f1395804-98e2-5d14-a2f4-cbe93380ee7a"
            )
        ]
    )
    func frozenVector(system: String, value: String, input: String, fullURL: String) throws {
        #expect(GroveFHIRExchangeIdentity.canonicalName(system: system, value: value) == input)
        #expect(try GroveFHIRExchangeIdentity.fullURL(system: system, value: value) == fullURL)
    }
}

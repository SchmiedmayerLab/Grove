//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveLLMOpenAI
import Testing


/// A function whose parameters leave most of the schema's optional fields unset.
private struct SparselyDescribedFunction: LLMTool {
    let name = "echo_token"
    let description = "Echoes the token it is given"

    @Parameter(description: "The token to echo back")
    var token: String
    @Parameter(description: "How many times to echo it")
    var count: Int?

    func execute() async throws -> String? {
        token
    }
}


/// Pins the wire shape of a generated tool schema.
///
/// A parameter that leaves `enum`, `format`, `pattern` or `const` unset must omit those keys rather than send them
/// as `null` — a schema carrying `"enum": null` is rejected outright with "None is not of type 'array'", which
/// takes function calling down entirely.
@Suite("LLM Function Schema Encoding")
struct LLMFunctionSchemaEncodingTests {
    @Test("An unset schema field is absent rather than null")
    func unsetFieldsAreOmitted() throws {
        let encoded = try JSONEncoder().encode(try SparselyDescribedFunction().schema)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(!json.contains("null"), "the schema should carry no explicit nulls; got: \(json)")

        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let properties = try #require(object["properties"] as? [String: Any])
        let token = try #require(properties["token"] as? [String: Any])
        #expect(token["type"] as? String == "string")
        #expect(token["description"] as? String == "The token to echo back")
        #expect(token["enum"] == nil, "an unset enum must not reach the wire")
        #expect(token["format"] == nil)
        #expect(token["pattern"] == nil)
        #expect(token["const"] == nil)
    }

    @Test("Only the non-optional parameters are required")
    func requiredListsTheNonOptionalParameters() throws {
        let encoded = try JSONEncoder().encode(try SparselyDescribedFunction().schema)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        let required = try #require(object["required"] as? [String])
        #expect(required == ["token"], "an optional parameter should not be required; got: \(required)")
    }
}

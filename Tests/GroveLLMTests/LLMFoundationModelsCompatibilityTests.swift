//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import FoundationModels
@testable import GeneratedOpenAIClient
@testable import GroveLLMOpenAI
import Testing


/// Covers presenting a `FoundationModels` tool as an ``LLMTool``.
///
/// The `@Test` and `@Suite` macros cannot be applied to availability-annotated declarations, so each test opens with
/// a runtime availability check.
@Suite("LLM FoundationModels Compatibility")
struct LLMFoundationModelsCompatibilityTests {
    @available(iOS 26, macOS 26, visionOS 26, *)
    struct GetWeather: Tool {
        @Generable
        struct Arguments {
            @Guide(description: "The city and state, e.g. San Francisco, CA")
            var location: String
        }

        let name = "get_weather"
        let description = "Get the current weather in a given location"

        func call(arguments: Arguments) async throws -> String {
            "The weather in \(arguments.location) is 30 degrees"
        }
    }


    @Test("A wrapped tool keeps its name and description")
    func identityCarriesOver() {
        guard #available(iOS 26, macOS 26, visionOS 26, *) else {
            return
        }
        let function = GetWeather().asLLMTool()
        #expect(function.name == "get_weather")
        #expect(function.description == "Get the current weather in a given location")
    }

    @Test("The tool's GenerationSchema becomes the function's parameter schema")
    func schemaComesFromTheTool() throws {
        guard #available(iOS 26, macOS 26, visionOS 26, *) else {
            return
        }
        let function = GetWeather().asLLMTool()
        let schema = try function.schema

        // Round-trip through JSON so the assertion is about the shape the request actually carries.
        let encoded = try JSONEncoder().encode(schema)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["type"] as? String == "object")
        let properties = try #require(object["properties"] as? [String: Any])
        #expect(properties["location"] != nil)
    }

    @Test("Arguments from the model reach the tool, and its output comes back")
    func argumentsRoundTripThroughExecute() async throws {
        guard #available(iOS 26, macOS 26, visionOS 26, *) else {
            return
        }
        let function = GetWeather().asLLMTool()
        let arguments = try function.arguments(from: Data(#"{"location":"San Francisco, CA"}"#.utf8))

        let output = try await function.execute(with: arguments)

        #expect(output == "The weather in San Francisco, CA is 30 degrees")
    }

    @Test("A call with no arguments does not trap")
    func missingArgumentsAreTolerated() async throws {
        guard #available(iOS 26, macOS 26, visionOS 26, *) else {
            return
        }
        let function = GetWeather().asLLMTool()
        // `location` is required, so decoding must fail rather than execute with a made-up value.
        await #expect(throws: (any Error).self) {
            try await function.execute()
        }
    }
}

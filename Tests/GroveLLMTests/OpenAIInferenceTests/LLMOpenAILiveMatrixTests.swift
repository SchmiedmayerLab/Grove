//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import Grove
@testable import GroveLLM
@testable import GroveLLMOpenAI
import GroveTesting
import Synchronization
import Testing


/// One cell of the matrix: an endpoint, the policy it is driven with, and whether the fallback is available.
struct LiveCombination: Sendable, CustomStringConvertible {
    let provider: LiveProvider
    let apiMode: LLMOpenAIAPIModePolicy
    let streamingFallback: Bool

    var description: String {
        "\(provider) / \(apiMode) / fallback \(streamingFallback ? "on" : "off")"
    }
}


/// One live endpoint the matrix runs against.
struct LiveProvider: Sendable, CustomStringConvertible {
    /// The OpenAI API itself.
    static let openAI = LiveProvider(
        name: "OpenAI",
        tokenVariable: "OPENAI_API_TOKEN",
        defaultURL: "https://api.openai.com/v1",
        model: "gpt-4.1-mini",
        streamsResponses: true
    )
    /// Stanford's LiteLLM gateway, which serves `/v1/responses` but cannot stream it.
    static let stanfordGateway = LiveProvider(
        name: "Stanford Gateway",
        tokenVariable: "GROVE_GATEWAY_TOKEN",
        urlVariable: "GROVE_GATEWAY_URL",
        defaultURL: "https://aiapi-prod.stanford.edu/v1",
        model: "gpt-5.4",
        streamsResponses: false
    )

    static let all: [LiveProvider] = [.openAI, .stanfordGateway]

    let name: String
    let tokenVariable: String
    var urlVariable: String?
    let defaultURL: String
    /// A model both API modes serve, so one model exercises the whole matrix.
    let model: OpenAIPlatformDefinition.ModelType
    /// Whether the endpoint can stream the Responses API. Where it cannot, the unstreamed fallback has to carry it.
    let streamsResponses: Bool

    var description: String { name }

    var token: String? {
        let token = ProcessInfo.processInfo.environment[tokenVariable]
        return (token?.isEmpty ?? true) ? nil : token
    }

    var url: URL? {
        let raw = urlVariable.flatMap { ProcessInfo.processInfo.environment[$0] } ?? defaultURL
        return URL(string: raw.isEmpty ? defaultURL : raw)
    }

    /// Whether this provider can serve the given policy at all, fallback included.
    func supports(_ apiMode: LLMOpenAIAPIModePolicy, streamingFallback: Bool) -> Bool {
        guard !streamsResponses else {
            return true
        }
        // Without a fallback, anything that resolves to the Responses API cannot work here.
        return streamingFallback || apiMode.resolve(for: model) == .chatCompletions
    }
}


/// A tool with an unmistakable, argument-dependent return value.
///
/// The echo is what makes a crossed argument visible: run two calls at once and each response has to carry back
/// its own token, not the other's.
private struct EchoFunction: LLMTool {
    let name = "echo_token"
    let description = "Echoes back the token it is given. Call it once for each token the user lists."

    @Parameter(description: "The token to echo back, exactly as given.")
    var token: String

    func execute() async throws -> String? {
        "echoed:\(token)"
    }
}


/// Runs the same conversations against every provider and API-mode combination.
///
/// The point is coverage of the cross product rather than of any one request: a policy that works against
/// `api.openai.com` can fail against a gateway, and a gateway that serves an endpoint may still not stream it.
@Suite(
    "LLM OpenAI Live Matrix",
    .disabled(
        if: LiveProvider.all.allSatisfy { $0.token == nil },
        "Set OPENAI_API_TOKEN and/or GROVE_GATEWAY_TOKEN to run the live matrix"
    )
)
final class LLMOpenAILiveMatrixTests {
    /// Every combination the matrix covers.
    static let combinations: [LiveCombination] = {
        var combinations: [LiveCombination] = []
        for provider in LiveProvider.all {
            for apiMode in [.perModel, .fixed(.responses), .fixed(.chatCompletions)] as [LLMOpenAIAPIModePolicy] {
                for streamingFallback in [true, false] {
                    combinations.append(
                        LiveCombination(provider: provider, apiMode: apiMode, streamingFallback: streamingFallback)
                    )
                }
            }
        }
        return combinations
    }()

    /// The combinations that should produce an answer.
    ///
    /// A provider with no token configured drops out entirely rather than failing: which credentials are on hand
    /// is a property of the machine, not of the code under test.
    static var workingCombinations: [LiveCombination] {
        combinations.filter { combination in
            combination.provider.token != nil
                && combination.provider.supports(combination.apiMode, streamingFallback: combination.streamingFallback)
        }
    }

    /// One working combination per provider, for the more expensive capability tests.
    static var perProviderCombinations: [LiveCombination] {
        LiveProvider.all.compactMap { provider in
            workingCombinations.first { $0.provider.name == provider.name }
        }
    }

    private var platformTask: Task<Void, Never>?

    @MainActor
    @Test("Every supported combination answers", arguments: workingCombinations)
    func answersAcrossTheMatrix(
        combination: LiveCombination
    ) async throws {
        let session = try makeSession(combination)
        session.context.append(userMessage: "Reply with exactly the word: ok")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(!output.isEmpty, "\(combination.provider) produced no output")
        #expect(session.context.contains { $0.role == .assistant }, "the answer should reach the context")
        #expect(session.context.last?.complete == true, "the answer should be marked complete")
    }

    @MainActor
    @Test("A Responses-API policy without a fallback fails where the endpoint cannot stream it")
    func unsupportedCombinationsFail() async throws {
        let provider = LiveProvider.stanfordGateway
        guard provider.token != nil else {
            return
        }

        let session = try makeSession(LiveCombination(provider: provider, apiMode: .fixed(.responses), streamingFallback: false))
        session.context.append(userMessage: "Reply with exactly the word: ok")
        do {
            for try await _ in try await session.generate() {}
            Issue.record("The gateway appears to stream /v1/responses now — the fallback may no longer be needed.")
        } catch {
            // Expected: the endpoint answers a streamed Responses request with a 500.
        }
    }

    @MainActor
    @Test("A multi-turn conversation keeps its history", arguments: perProviderCombinations)
    func keepsHistoryAcrossTurns(
        combination: LiveCombination
    ) async throws {
        let session = try makeSession(combination)
        session.context.append(userMessage: "My favourite colour is chartreuse. Reply with exactly: noted")
        for try await _ in try await session.generate() {}

        session.context.append(userMessage: "What is my favourite colour? Reply with just the colour.")
        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        #expect(
            output.lowercased().contains("chartreuse"),
            "\(combination.provider) lost the earlier turn; got: \(output)"
        )
    }

    @MainActor
    @Test("A tool is offered, called, and its output fed back", arguments: perProviderCombinations)
    func callsATool(
        combination: LiveCombination
    ) async throws {
        let session = try makeSession(combination) {
            EchoFunction()
        }
        session.context.append(userMessage: "Call echo_token with the token \"alpha\", then tell me what it returned.")

        var output = ""
        for try await piece in try await session.generate() {
            output.append(piece)
        }

        let toolResponses = session.context.filter { $0.isToolCallResponse }
        #expect(!toolResponses.isEmpty, "\(combination.provider) never called the tool")
        #expect(
            toolResponses.contains { $0.content.contains("echoed:alpha") },
            "the tool's own output should come back; got: \(toolResponses.map(\.content))"
        )
        #expect(!output.isEmpty)
    }

    /// Parallel tool calls are where a shared function instance shows itself: each call has to come back with the
    /// argument it was given, not with whichever argument was injected last.
    @MainActor
    @Test("Parallel calls to one tool each keep their own arguments", arguments: perProviderCombinations)
    func parallelToolCallsDoNotCrossArguments(
        combination: LiveCombination
    ) async throws {
        let session = try makeSession(combination) {
            EchoFunction()
        }
        session.context.append(
            userMessage: """
                Call echo_token three times in one go — once with the token "alpha", once with "bravo", and once with \
                "charlie". Issue all three calls together, then summarise what came back.
                """
        )

        for try await _ in try await session.generate() {}

        // Pair each response with the call it answers. Comparing the set of returned tokens instead would report a
        // model that simply repeated an argument as a crossed one, and would miss a cross between equal arguments.
        var requestedTokens: [String: String] = [:]
        for entity in session.context {
            guard case .toolCalls(let calls) = entity.role else {
                continue
            }
            for call in calls {
                guard let data = call.arguments.data(using: .utf8),
                      let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = arguments["token"] as? String else {
                    continue
                }
                requestedTokens[call.id] = token
            }
        }
        guard requestedTokens.count > 1 else {
            // A model is free to answer with a single call; nothing to prove about crossing in that case.
            return
        }

        var checked = 0
        for entity in session.context {
            guard case .toolCallResponse(let id, _) = entity.role, let requested = requestedTokens[id] else {
                continue
            }
            checked += 1
            #expect(
                entity.content.contains("echoed:\(requested)"),
                "the call \(id) asked for \(requested) but its result was \(entity.content)"
            )
        }
        #expect(checked == requestedTokens.count, "every requested call should have produced a result")
    }

    @MainActor
    private func makeSession(
        _ combination: LiveCombination,
        @LLMToolBuilder _ functions: () -> _LLMToolCollection = { _LLMToolCollection() }
    ) throws -> LLMOpenAISession {
        let token = try #require(combination.provider.token, "\(combination.provider.tokenVariable) is not set")
        let url = try #require(combination.provider.url)

        let platform = LLMOpenAIPlatform(
            configuration: .init(
                serverUrl: url,
                authToken: .constant(token),
                apiMode: combination.apiMode,
                streamingFallback: combination.streamingFallback
            )
        )
        let runner = LLMRunner { platform }
        withDependencyResolution { runner }
        platformTask = Task { await platform.run() }

        return platform(
            with: LLMOpenAISchema(
                parameters: .init(modelType: combination.provider.model),
                injectIntoContext: true,
                functions
            )
        )
    }

    deinit {
        platformTask?.cancel()
    }
}


extension LLMContextEntity {
    fileprivate var isToolCallResponse: Bool {
        if case .toolCallResponse = role {
            true
        } else {
            false
        }
    }
}

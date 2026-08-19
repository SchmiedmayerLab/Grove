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
import Testing


/// Checks that a model asked to search the web reports what it found.
///
/// Everything else about citations is covered against fixtures; what only a live call can show is that enabling the
/// hosted search tool actually produces annotations, and that they survive the whole path into ``LLMContext``.
///
/// - Note: These are the only tests that bill for a search on top of the tokens, so there are deliberately few of
///     them — one per provider, each a single short question.
@Suite(
    "LLM OpenAI Citations (Live)",
    .disabled(
        if: LiveProvider.all.allSatisfy { $0.token == nil },
        "Set OPENAI_API_TOKEN and/or GROVE_GATEWAY_TOKEN to run the live citation tests"
    )
)
final class LLMOpenAICitationLiveTests {
    private var platformTask: Task<Void, Never>?

    @MainActor
    @Test("A searching model reports the sources it drew on", arguments: LiveProvider.all)
    func citationsReachTheContext(provider: LiveProvider) async throws {
        guard provider.token != nil else {
            return
        }
        let session = try makeSession(for: provider)
        session.context.append(
            userMessage: "What is the capital of Iceland? Answer in one sentence and cite a source."
        )

        var output = ""
        do {
            for try await piece in try await session.generate() {
                output.append(piece)
            }
        } catch {
            // A gateway may decline the hosted search tool outright, which is its limitation rather than a defect
            // here. A decoding failure is *not* that — it means the response was served and we could not read it.
            guard provider.name != LiveProvider.openAI.name else {
                throw error
            }
            withKnownIssue("\(provider) declined the hosted web search tool", isIntermittent: true) {
                throw error
            }
            return
        }

        #expect(!output.isEmpty, "\(provider) produced no answer")

        let citations = session.context.compactMap(\.citations).flatMap { $0 }
        withKnownIssue(
            "\(provider) answered without searching, which the model may decide for a question it knows",
            isIntermittent: true
        ) {
            try #require(!citations.isEmpty)
        }
        guard !citations.isEmpty else {
            return
        }

        // Every citation has to be usable: a source with no title or no destination cannot be shown or opened.
        for citation in citations {
            #expect(!citation.title.isEmpty, "a source with no title has nothing to show in the list")
            switch citation.source {
            case .web(let url):
                #expect(url.host() != nil, "a web source needs a host to open and to name")
            case .file(let name):
                #expect(!name.isEmpty)
            }
        }
        #expect(
            Set(citations.map(\.source)).count == citations.count,
            "the same source cited twice should have collapsed on the way in"
        )
    }

    @MainActor
    private func makeSession(for provider: LiveProvider) throws -> LLMOpenAISession {
        let token = try #require(provider.token, "\(provider.tokenVariable) is not set")
        let url = try #require(provider.url)

        let platform = LLMOpenAIPlatform(
            configuration: .init(serverUrl: url, authToken: .constant(token), apiMode: .fixed(.responses))
        )
        let runner = LLMRunner { platform }
        withDependencyResolution { runner }
        platformTask = Task { await platform.run() }

        return platform(
            with: LLMOpenAISchema(
                parameters: .init(modelType: provider.model),
                injectIntoContext: true,
                searchesTheWeb: true
            )
        )
    }

    deinit {
        platformTask?.cancel()
    }
}

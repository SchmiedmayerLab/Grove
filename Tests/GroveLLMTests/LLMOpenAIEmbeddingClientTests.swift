//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
@testable import GroveLLM
@testable import GroveLLMOpenAI
import HTTPTypes
import OpenAPIRuntime
import Testing


@Suite("LLMOpenAIEmbeddingClient")
struct LLMOpenAIEmbeddingClientTests {
    private let endpointA = URL(string: "https://embeddings-a.example/v1")!
    private let endpointB = URL(string: "https://embeddings-b.example/v1")!


    // MARK: - Helpers

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                stored = newValue
            }
        }
    }

    private struct RecordingTransport: ClientTransport {
        let handler: @Sendable (HTTPRequest, HTTPBody?, URL, String) async throws -> (HTTPResponse, HTTPBody?)

        func send(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID: String
        ) async throws -> (HTTPResponse, HTTPBody?) {
            try await handler(request, body, baseURL, operationID)
        }
    }

    private func fixtureResponse(
        embeddings: [(index: Int, vector: [Float])],
        model: String = "text-embedding-3-small",
        promptTokens: Int = 3,
        totalTokens: Int = 3,
        requestID: String? = "req_fixture",
        status: HTTPResponse.Status = .ok
    ) throws -> (HTTPResponse, HTTPBody) {
        var embeddingObjects: [[String: Any]] = []
        for item in embeddings {
            embeddingObjects.append([
                "object": "embedding",
                "index": item.index,
                "embedding": item.vector
            ])
        }
        let payload: [String: Any] = [
            "object": "list",
            "model": model,
            "data": embeddingObjects,
            "usage": [
                "prompt_tokens": promptTokens,
                "total_tokens": totalTokens
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        var response = HTTPResponse(status: status)
        if let requestID, let name = HTTPField.Name("x-request-id") {
            response.headerFields[name] = requestID
        }
        return (response, HTTPBody(bodyData))
    }

    private func makeClient(
        serverURL: URL,
        authToken: RemoteLLMInferenceAuthToken,
        transport: RecordingTransport,
        retryPolicy: RetryPolicy = .never,
        maxBatchCount: Int = LLMOpenAIEmbeddingClient.defaultMaxBatchCount,
        maxInputBytes: Int = LLMOpenAIEmbeddingClient.defaultMaxInputBytes,
        maxRequestBytes: Int = LLMOpenAIEmbeddingClient.defaultMaxRequestBytes,
        maxResponseBytes: Int = LLMOpenAIEmbeddingClient.defaultMaxResponseBytes
    ) throws -> LLMOpenAIEmbeddingClient {
        try LLMOpenAIEmbeddingClient(
            serverURL: serverURL,
            authToken: authToken,
            retryPolicy: retryPolicy,
            maxBatchCount: maxBatchCount,
            maxInputBytes: maxInputBytes,
            maxRequestBytes: maxRequestBytes,
            maxResponseBytes: maxResponseBytes,
            transport: transport
        )
    }


    // MARK: - Pre-dispatch validation

    @Test("Rejects empty batches before dispatch")
    func rejectsEmptyBatch() async throws {
        let dispatched = Flag()
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                dispatched.value = true
                throw CancellationError()
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.emptyBatch) {
            _ = try await client.embed([], model: "text-embedding-3-small", dimensions: nil)
        }
        #expect(!dispatched.value)
    }

    @Test("Rejects empty strings before dispatch")
    func rejectsEmptyString() async throws {
        let dispatched = Flag()
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                dispatched.value = true
                throw CancellationError()
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.emptyInput) {
            _ = try await client.embed(["ok", ""], model: "text-embedding-3-small", dimensions: nil)
        }
        #expect(!dispatched.value)
    }

    @Test("Rejects non-positive requested dimensions before dispatch")
    func rejectsInvalidDimensions() async throws {
        let dispatched = Flag()
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                dispatched.value = true
                throw CancellationError()
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.invalidDimensions) {
            _ = try await client.embed(["hello"], model: "text-embedding-3-small", dimensions: 0)
        }
        #expect(!dispatched.value)
    }

    @Test("Rejects oversized inputs before dispatch")
    func rejectsOversizedInput() async throws {
        let dispatched = Flag()
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                dispatched.value = true
                throw CancellationError()
            },
            maxInputBytes: 4
        )
        await #expect(throws: LLMOpenAIEmbeddingError.inputTooLarge) {
            _ = try await client.embed(["too-large"], model: "text-embedding-3-small", dimensions: nil)
        }
        #expect(!dispatched.value)
    }

    @Test("Rejects invalid retry attempt counts at initialization")
    func rejectsInvalidRetryPolicy() {
        #expect(throws: LLMOpenAIEmbeddingError.invalidRetryPolicy) {
            _ = try LLMOpenAIEmbeddingClient(
                serverURL: endpointA,
                authToken: .constant("token"),
                retryPolicy: .attempts(0),
                transport: RecordingTransport { _, _, _, _ in
                    throw CancellationError()
                }
            )
        }
    }


    // MARK: - Response handling

    @Test("Restores out-of-order embedding indices to input order")
    func restoresOutOfOrderIndices() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [
                        (index: 2, vector: [0.2, 0.02]),
                        (index: 0, vector: [0.0, 0.00]),
                        (index: 1, vector: [0.1, 0.01])
                    ],
                    requestID: "req_reorder"
                )
            }
        )

        let result = try await client.embed(
            ["a", "b", "c"],
            model: "text-embedding-3-small",
            dimensions: 2
        )
        #expect(result.vectors == [[0.0, 0.00], [0.1, 0.01], [0.2, 0.02]])
        #expect(result.dimensions == 2)
        #expect(result.model == "text-embedding-3-small")
        #expect(result.usage == LLMEmbeddingUsage(inputTokens: 3, totalTokens: 3))
        #expect(result.providerRequestID == "req_reorder")
    }

    @Test("Rejects duplicate embedding indices")
    func rejectsDuplicateIndices() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [
                        (index: 0, vector: [0.1]),
                        (index: 0, vector: [0.2])
                    ]
                )
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.malformedResponse) {
            _ = try await client.embed(["a", "b"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Rejects missing embedding indices")
    func rejectsMissingIndices() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [
                        (index: 0, vector: [0.1])
                    ]
                )
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.malformedResponse) {
            _ = try await client.embed(["a", "b"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Rejects out-of-range embedding indices")
    func rejectsOutOfRangeIndices() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [
                        (index: 0, vector: [0.1]),
                        (index: 5, vector: [0.2])
                    ]
                )
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.malformedResponse) {
            _ = try await client.embed(["a", "b"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Rejects inconsistent vector dimensions")
    func rejectsInconsistentDimensions() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [
                        (index: 0, vector: [0.1, 0.2]),
                        (index: 1, vector: [0.3])
                    ]
                )
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.malformedResponse) {
            _ = try await client.embed(["a", "b"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Rejects empty embedding vectors")
    func rejectsEmptyVectors() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [
                        (index: 0, vector: [])
                    ]
                )
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.malformedResponse) {
            _ = try await client.embed(["a"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Rejects oversized response bodies before decoding")
    func rejectsOversizedResponses() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                let body = HTTPBody(Data(repeating: 0x61, count: 64))
                return (HTTPResponse(status: .ok), body)
            },
            maxResponseBytes: 16
        )
        await #expect(throws: LLMOpenAIEmbeddingError.responseTooLarge) {
            _ = try await client.embed(["a"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Propagates provider HTTP failures without fallback")
    func propagatesProviderErrors() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                (HTTPResponse(status: .badRequest), HTTPBody(Data("{\"error\":\"bad\"}".utf8)))
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.provider(.invalidRequest)) {
            _ = try await client.embed(["a"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Rejects negative or inconsistent usage totals")
    func rejectsInvalidUsage() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [(index: 0, vector: [0.1])],
                    promptTokens: 5,
                    totalTokens: 2
                )
            }
        )
        await #expect(throws: LLMOpenAIEmbeddingError.malformedResponse) {
            _ = try await client.embed(["a"], model: "text-embedding-3-small", dimensions: nil)
        }
    }

    @Test("Leaves providerRequestID nil when response headers omit it")
    func nilRequestIDWhenMissing() async throws {
        let client = try makeClient(
            serverURL: endpointA,
            authToken: .constant("token-a"),
            transport: RecordingTransport { _, _, _, _ in
                try self.fixtureResponse(
                    embeddings: [(index: 0, vector: [0.5, 0.25])],
                    requestID: nil
                )
            }
        )
        let result = try await client.embed(["a"], model: "text-embedding-3-small", dimensions: nil)
        #expect(result.providerRequestID == nil)
    }


    // MARK: - Credential isolation

    @Test("Distinct clients keep distinct tokens and endpoints")
    func isolatesCredentialsAndEndpoints() async throws {
        final class Recorder: @unchecked Sendable {
            let lock = NSLock()
            var authHeaders: [String?] = []
            var baseURLs: [URL] = []

            func append(auth: String?, baseURL: URL) {
                lock.lock()
                defer { lock.unlock() }
                authHeaders.append(auth)
                baseURLs.append(baseURL)
            }
        }
        let recorder = Recorder()

        let transportA = RecordingTransport { request, _, baseURL, _ in
            recorder.append(auth: request.headerFields[.authorization], baseURL: baseURL)
            return try self.fixtureResponse(embeddings: [(index: 0, vector: [0.1])])
        }
        let transportB = RecordingTransport { request, _, baseURL, _ in
            recorder.append(auth: request.headerFields[.authorization], baseURL: baseURL)
            return try self.fixtureResponse(embeddings: [(index: 0, vector: [0.2])])
        }

        let clientA = try makeClient(
            serverURL: endpointA,
            authToken: .closure { "token-a" },
            transport: transportA
        )
        let clientB = try makeClient(
            serverURL: endpointB,
            authToken: .closure { "token-b" },
            transport: transportB
        )

        _ = try await clientA.embed(["a"], model: "text-embedding-3-small", dimensions: nil)
        _ = try await clientB.embed(["b"], model: "text-embedding-3-small", dimensions: nil)

        #expect(recorder.authHeaders == ["Bearer token-a", "Bearer token-b"])
        #expect(recorder.baseURLs == [endpointA, endpointB])
    }
}

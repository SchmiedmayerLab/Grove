//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import HTTPTypes
import OpenAPIRuntime


/// Bounds HTTP response bodies before the generated OpenAPI decoder consumes them.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ResponseByteLimitMiddleware: ClientMiddleware {
    let maxResponseBytes: Int


    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard let responseBody else {
            return (response, nil)
        }

        var collected = Data()
        collected.reserveCapacity(min(maxResponseBytes, 64 * 1024))
        for try await chunk in responseBody {
            let nextCount = collected.count + chunk.count
            guard nextCount <= maxResponseBytes else {
                throw LLMOpenAIEmbeddingError.responseTooLarge
            }
            collected.append(contentsOf: chunk)
        }
        return (response, HTTPBody(collected))
    }
}


/// Captures a provider request identifier from embedding response headers when present.
@available(iOS 18, macOS 15, watchOS 11, *)
final class EmbeddingRequestIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
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


@available(iOS 18, macOS 15, watchOS 11, *)
struct EmbeddingRequestIDMiddleware: ClientMiddleware {
    let box: EmbeddingRequestIDBox


    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        for name in ["x-request-id", "x-openai-request-id", "openai-request-id"] {
            if let fieldName = HTTPField.Name(name), let requestID = response.headerFields[fieldName] {
                box.value = requestID
                break
            }
        }
        return (response, responseBody)
    }
}

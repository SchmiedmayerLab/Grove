//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import HTTPTypes
import OpenAPIRuntime
import Synchronization
import Testing


struct RetryMiddlewareTests {
    @Test(arguments: [false, true])
    func cancelledInvocationStopsBeforeItsNextDispatch(cancelBeforeFirst: Bool) async throws {
        let middleware = RetryMiddleware(policy: .attempts(2), delay: .none)
        let url = try #require(URL(string: "https://example.invalid"))
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.invalid", path: "/")
        let cancelled = Mutex(cancelBeforeFirst)
        var calls = 0

        do {
            _ = try await RetryMiddleware.$invocationIsCancelled.withValue({ cancelled.withLock { $0 } }) {
                try await middleware.intercept(request, body: nil, baseURL: url, operationID: "test") { _, _, _ in
                    calls += 1
                    cancelled.withLock { $0 = true }
                    return (.init(status: .serviceUnavailable), nil)
                }
            }
            Issue.record("Expected invocation cancellation")
        } catch is CancellationError {
            #expect(calls == (cancelBeforeFirst ? 0 : 1))
        }

        let (response, _) = try await middleware.intercept(request, body: nil, baseURL: url, operationID: "next") { _, _, _ in
            (.init(status: .ok), nil)
        }
        #expect(response.status == .ok)
    }

    @Test(arguments: [URLError.Code.cancelled, .timedOut], [false, true])
    func retriesOnlyTransientTransportErrors(_ code: URLError.Code, wrapped: Bool) async throws {
        let middleware = RetryMiddleware(policy: .attempts(2), delay: .none)
        let url = try #require(URL(string: "https://example.invalid"))
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.invalid", path: "/")
        var calls = 0

        do {
            let (response, _) = try await middleware.intercept(request, body: nil, baseURL: url, operationID: "test") { _, _, _ in
                calls += 1
                if calls == 1 {
                    if wrapped {
                        throw ClientError(operationID: "test", operationInput: (), causeDescription: "Transport", underlyingError: URLError(code))
                    }
                    throw URLError(code)
                }
                return (.init(status: .ok), nil)
            }
            #expect(code == .timedOut)
            #expect(response.status == .ok)
        } catch {
            // A transport cancellation nobody requested is not retried and stays a transport failure.
            #expect(code == .cancelled)
            #expect(RetryMiddleware.isTransportCancellation(error))
            #expect(!(error is CancellationError))
        }
        #expect(calls == (code == .cancelled ? 1 : 2))
    }
}

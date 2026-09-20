//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveKeychainStorage
import GroveLLM
import GroveLLMOpenAI
import OpenAPIURLSession
import os


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeSession {
    /// A session that is ready, generating, or running a tool is set up; opening a second socket for it would double
    /// every event. A fresh or failed session connects, and a caller that finds one loading waits for that setup.
    @MainActor private var needsSetup: Bool {
        switch state {
        case .uninitialized, .loading, .error:
            true
        default:
            false
        }
    }

    /// Ensures the Realtime API session is set up and ready to use.
    ///
    /// If the session is already ready, it returns immediately.
    /// Otherwise, it initializes the connection and prepares the session for streaming.
    ///
    /// - Throws: An error if setup fails or if the operation is cancelled.
    @MainActor
    func ensureSetup() async throws {
        guard needsSetup else {
            return
        }

        try await setupSemaphore.waitCheckingCancellation()
        defer { setupSemaphore.signal() }

        guard needsSetup else {
            return
        }

        try await self.setup()
    }
    
    /// Performs the initial setup by initializing the client and starting event listeners.
    ///
    /// - Throws: An error if client initialization fails.
    @MainActor
    private func setup() async throws {
        state = .loading
        stopEventHandling()
        await transcripts.reset()
        try await self.initializeClient()
        // Register before exposing readiness, so the first turn cannot precede the context listener.
        let broadcaster = await apiConnection.eventStream
        let events = await broadcaster.observe()
        transcribesUserAudio = await apiConnection.inputTranscriptionEnabled
        listenToLLMEvents(events, connectionId: await apiConnection.connectionId, broadcaster: broadcaster)
        state = .ready
    }

    /// Retrieves the auth token and opens the WebSocket connection to the Realtime API.
    ///
    /// - Throws: An error if the auth token is missing or the connection fails.
    private func initializeClient() async throws {
        let authToken = try await (schema.parameters.overwritingAuthToken ?? platform.configuration.authToken)
            .getToken(keychainStorage: keychainStorage)

        guard let authToken = authToken else {
            Self.logger.error("LLMOpenAIRealtimeSession: Auth Token is nil")
            throw LLMOpenAIError.missingAPITokenInKeychain
        }

        do {
            try await apiConnection.open(
                token: authToken,
                schema: schema,
                serverUrl: schema.parameters.overwritingServerUrl ?? platform.configuration.serverUrl
            )
        } catch let error as any LLMError {
            Self.logger.error("GroveLLMOpenAIRealtime: Encountered LLMError during initialization: \(error)")
            await apiConnection.cancel()
            await MainActor.run { self.state = .error(error: error) }
            throw error
        } catch {
            Self.logger.error("GroveLLMOpenAIRealtime: Encountered unknown error during initialization: \(error)")
            await apiConnection.cancel()
            // Left loading, the session would count as set up and never connect again.
            await MainActor.run { self.state = .error(error: LLMOpenAIError.connectivityIssues(error)) }
            throw error
        }
    }
}

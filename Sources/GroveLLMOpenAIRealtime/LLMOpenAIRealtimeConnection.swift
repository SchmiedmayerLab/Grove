//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import GroveLLM
import GroveLLMOpenAI
import os


@available(iOS 18, macOS 15, watchOS 11, *)
actor LLMOpenAIRealtimeConnection {
    private typealias FunctionCallArgs = Components.Schemas.RealtimeServerEventResponseFunctionCallArgumentsDone
    private typealias RealtimeErrorEvent = Components.Schemas.RealtimeServerEventError

    enum RealtimeError: LLMError {
        case malformedUrlError
        case socketNotFoundError
        case openAIError(error: Components.Schemas.RealtimeServerEventError.errorPayload)
        case eventSessionUpdateSerialisationError
    }
    
    private static let logger = Logger(subsystem: "org.grovealliance", category: "GroveLLMOpenAIRealtime")
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private var eventLoopTask: Task<Void, any Error>?

    // Websocket Connection
    private var socket: URLSessionWebSocketTask?
    private lazy var urlSession = URLSession(configuration: .default)

    // The event stream which gets sent in session.events()
    private let eventStream = EventBroadcaster<LLMRealtimeAudioEvent>()

    // Handling of the setup: only finish whenever the connection to API has been successful
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    // A request while a response is active is refused, and an out-of-band one can overlap the conversation's, so
    // every response in flight is tracked and requests wait until none is.
    var activeResponses: Set<String> = []
    // Requests already sent whose `response.created` has not arrived yet, by their event id and in the order they
    // were sent; they count as active too, and a refusal that names the event id releases them.
    var pendingResponseRequests: [String] = []
    // In arrival order: turns are handed out one at a time, since two requests released together would both be
    // sent and, if one is out-of-band, both be spoken.
    var idleWaiters: [IdleWaiter] = []

    func cancel() {
        eventLoopTask?.cancel()
        eventLoopTask = nil
        socket?.cancel()
        socket = nil
        resetResponseTracking()
    }
    
    /// Returns a stream of Realtime events.
    ///
    /// The returned stream yields `LLMRealtimeAudioEvent` values such as audio deltas, transcript
    /// updates, function call requests, and lifecycle notifications.
    ///
    /// The stream obtained by calling this method finishes when the connection ends or the consuming task is cancelled.
    /// Errors are also emitted in this stream.
    ///
    /// - Returns: An `AsyncThrowingStream` emitting `LLMRealtimeAudioEvent` values.
    func events() async -> AsyncThrowingStream<LLMRealtimeAudioEvent, any Error> {
        // Creates an AsyncThrowingStream to listen to (so that there can be multiple listeners)
        await eventStream.observe()
    }
    
    func sendMessage(_ object: some Encodable) async throws {
        guard let socket else {
            throw RealtimeError.socketNotFoundError
        }
        let objectJson = try Self.encoder.encode(object)
        try await socket.send(.string(String(decoding: objectJson, as: UTF8.self)))
    }
    
    /// Opens the socket to the `/realtime` endpoint next to `serverUrl` and starts the event loop, which runs until `cancel()`.
    /// Returns once the session is ready: after `session.updated` when the session configures itself, after `session.created` otherwise.
    func open(token: String, schema: LLMOpenAIRealtimeSchema, serverUrl: URL) async throws {
        let realtimeApiUrl = try Self.realtimeSocketUrl(from: serverUrl, model: schema.parameters.modelType)
        
        resetResponseTracking()
        var req = URLRequest(url: realtimeApiUrl)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let webSocketTask = urlSession.webSocketTask(with: req)
        webSocketTask.resume()
        socket = webSocketTask
        
        try await startEventLoop(schema: schema)
    }
        
    /// Starts the event loop, which runs until calling `cancel()`
    /// Waits until the event loop has succesfully been initialized: only continues once session.created event is successfully received from socket
    private func startEventLoop(schema: LLMOpenAIRealtimeSchema) async throws {
        eventLoopTask = Task {
            do {
                try await self.eventLoop(schema: schema)
            } catch is CancellationError {
                readyContinuation?.resume(throwing: CancellationError())
                readyContinuation = nil
            } catch let error as NSError where
                        error.domain == NSPOSIXErrorDomain &&
                        error.code == Int(POSIXErrorCode.ENOTCONN.rawValue) &&
                        Task.isCancelled {
                // When Task got cancelled, resulting in Socket not connected error
                readyContinuation?.resume(throwing: CancellationError())
                readyContinuation = nil
            } catch {
                Self.logger.error("GroveLLMOpenAiRealtime: LLMOpenAIRealtimeConnection eventLoop() failed with error: \(error)")
                // A socket that drops after setup ends the session for everyone listening; a silent stream would
                // leave them waiting forever.
                readyContinuation?.resume(throwing: error)
                readyContinuation = nil
                await eventStream.finish(throwing: error)
            }
        }
        // Await until we obtain session.created from OpenAI
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
        }
    }
    
    // swiftlint:disable function_body_length cyclomatic_complexity closure_body_length
    /// Event loop function
    private func eventLoop(schema: LLMOpenAIRealtimeSchema) async throws {
        guard let socket = socket else {
            throw RealtimeError.socketNotFoundError
        }

        try await withTaskCancellationHandler {
            while true {
                let message = try await socket.receive()
                
                guard case let .string(text) = message else {
                    Self.logger.warning("RealtimeAPI Message is not of type .string")
                    continue
                }
                
                guard let messageJsonData = text.data(using: .utf8),
                          let messageDict = try? JSONSerialization.jsonObject(with: messageJsonData, options: [])  as? [String: Any]
                else {
                    Self.logger.warning("Invalid message format: \(text)")
                    continue
                }

                guard let type = messageDict["type"] as? String else {
                    Self.logger.warning("RealtimeAPI Message has no type")
                    continue
                }

                switch type {
                case "session.created":
                    switch schema.parameters.sessionConfiguration {
                    case .client:
                        try await sendSessionUpdate(schema: schema)
                    case .server:
                        readyContinuation?.resume()
                        readyContinuation = nil
                    }
                case "session.updated":
                    readyContinuation?.resume()
                    readyContinuation = nil
                case "response.created":
                    responseCreated(id: (messageDict["response"] as? [String: Any])?["id"] as? String)
                case "response.done":
                    responseFinished(id: (messageDict["response"] as? [String: Any])?["id"] as? String)
                // The names without `output_` are the beta interface's; both are accepted so a gateway still
                // on that interface keeps working.
                case "response.output_audio.delta", "response.audio.delta":
                    guard let deltaBase64Str = messageDict["delta"] as? String,
                          let deltaPcmData = Data(base64Encoded: deltaBase64Str) else {
                        continue
                    }
                    let llmEvent = LLMRealtimeAudioEvent.audioDelta(deltaPcmData)
                    await eventStream.broadcast(llmEvent)
                case "response.output_audio.done", "response.audio.done":
                    await eventStream.broadcast(LLMRealtimeAudioEvent.audioDone)
                case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
                    let transcript = messageDict["delta"] as? String ?? ""
                    await eventStream.broadcast(LLMRealtimeAudioEvent.assistantTranscriptDelta(transcript))
                case "response.output_audio_transcript.done", "response.audio_transcript.done":
                    let transcript = messageDict["transcript"] as? String ?? ""
                    await eventStream.broadcast(LLMRealtimeAudioEvent.assistantTranscriptDone(transcript))
                case "conversation.item.input_audio_transcription.delta":
                    let event = try Self.decoder.decode(LLMRealtimeAudioEvent.TranscriptDelta.self, from: messageJsonData)
                    await eventStream.broadcast(LLMRealtimeAudioEvent.userTranscriptDelta(event))
                case "conversation.item.input_audio_transcription.completed":
                    let event = try Self.decoder.decode(LLMRealtimeAudioEvent.TranscriptDone.self, from: messageJsonData)
                    await eventStream.broadcast(LLMRealtimeAudioEvent.userTranscriptDone(event))
                case "conversation.item.input_audio_transcription.failed":
                    let event = try Self.decoder.decode(LLMRealtimeAudioEvent.TranscriptFailed.self, from: messageJsonData)
                    await eventStream.broadcast(LLMRealtimeAudioEvent.userTranscriptFailed(event))
                case "input_audio_buffer.speech_started":
                    let event = try Self.decoder.decode(LLMRealtimeAudioEvent.SpeechStarted.self, from: messageJsonData)
                    await eventStream.broadcast(LLMRealtimeAudioEvent.speechStarted(event))
                case "input_audio_buffer.speech_stopped":
                    let event = try Self.decoder.decode(LLMRealtimeAudioEvent.SpeechStopped.self, from: messageJsonData)
                    await eventStream.broadcast(LLMRealtimeAudioEvent.speechStopped(event))
                case "response.function_call_arguments.done":
                    let event = try Self.decoder.decode(FunctionCallArgs.self, from: messageJsonData)
                    await eventStream.broadcast(LLMRealtimeAudioEvent.functionCallRequested(
                        LLMOpenAIStreamResult.FunctionCall(
                            name: event.name,
                            id: event.call_id,
                            arguments: event.arguments
                        )
                    ))
                case "error":
                    let event = try Self.decoder.decode(RealtimeErrorEvent.self, from: messageJsonData)
                    let error = RealtimeError.openAIError(error: event.error)
                    if let readyContinuation {
                        // Before the session is up there is nothing to keep going.
                        readyContinuation.resume(with: .failure(error))
                        self.readyContinuation = nil
                        await eventStream.finish(throwing: error)
                    } else {
                        // A refused request is the server's answer to one event, not the end of the session; the
                        // request it names will never be created, so it must not keep later ones waiting.
                        Self.logger.error("GroveLLMOpenAIRealtime: The server refused an event: \(event.error.message)")
                        if let eventId = event.error.event_id {
                            withdraw(eventId)
                        }
                        await eventStream.broadcast(LLMRealtimeAudioEvent.serverError(event.error))
                    }
                default:
                    break
                }
            }
        } onCancel: {
            Task {
                await eventStream.finish()
            }
        }
    }
    
    private func sendSessionUpdate(schema: LLMOpenAIRealtimeSchema) async throws {
        typealias RealtimeClientEventSessionUpdate = Components.Schemas.RealtimeClientEventSessionUpdate
        typealias RealtimeSessionCreateRequestGA = Components.Schemas.RealtimeSessionCreateRequestGA
        typealias ToolsPayload = RealtimeSessionCreateRequestGA.toolsPayloadPayload

        let tools: [ToolsPayload] = try schema.functions.values.compactMap { function in
            let encodedSchema = try Self.encoder.encode(try function.schema)
            let jsonObject = try JSONSerialization.jsonObject(with: encodedSchema) as? [String: any Sendable] ?? [:]

            return .RealtimeFunctionTool(
                Components.Schemas.RealtimeFunctionTool(
                    _type: .function,
                    name: function.name,
                    description: function.description,
                    parameters: try .init(unvalidatedValue: jsonObject)
                )
            )
        }

        let transcriptionSettings = schema.parameters.transcriptionSettings
        let transcription: Components.Schemas.AudioTranscription? = if let transcriptionSettings {
            Components.Schemas.AudioTranscription(
                model: .init(value1: transcriptionSettings.model.rawValue),
                language: transcriptionSettings.language?.identifier,
                prompt: transcriptionSettings.prompt
            )
        } else {
            nil
        }

        let eventSessionUpdate = RealtimeClientEventSessionUpdate(
            _type: .session_period_update,
            session: .RealtimeSessionCreateRequestGA(
                RealtimeSessionCreateRequestGA(
                    _type: .realtime,
                    instructions: schema.parameters.systemPrompt,
                    audio: .init(
                        input: .init(
                            transcription: transcription
                        ),
                        output: .init(
                            voice: schema.parameters.voice.map { val in
                                Components.Schemas.VoiceIdsOrCustomVoice(
                                    value1: .init(value1: val.rawValue)
                                )
                            }
                        )
                    ),
                    tools: tools
                )
            )
        )
        
        let eventSessionUpdateData = try Self.encoder.encode(eventSessionUpdate)
        guard var eventSessionUpdateJson = try JSONSerialization.jsonObject(with: eventSessionUpdateData) as? [String: Any],
              var session = eventSessionUpdateJson["session"] as? [String: Any] else {
            throw RealtimeError.eventSessionUpdateSerialisationError
        }

        // Turn detection is set on the JSON directly: JSONEncoder omits `nil`, and an explicit `null` is what turns it
        // off. The GA interface keeps it under the input audio settings.
        var audio = session["audio"] as? [String: Any] ?? [:]
        var input = audio["input"] as? [String: Any] ?? [:]
        if let turnDetectionSettings = schema.parameters.turnDetectionSettings {
            let turnDetectionData = try Self.encoder.encode(turnDetectionSettings)
            input["turn_detection"] = try JSONSerialization.jsonObject(with: turnDetectionData, options: [])
        } else {
            // turnDetectionSettings set to nil: Explicitely set turn_detection to "null" to disable turn detection entirely
            input["turn_detection"] = NSNull()
        }
        audio["input"] = input
        session["audio"] = audio
        eventSessionUpdateJson["session"] = session

        let finalData = try JSONSerialization.data(withJSONObject: eventSessionUpdateJson)


        try await socket?.send(.string(String(decoding: finalData, as: UTF8.self)))
    }
}

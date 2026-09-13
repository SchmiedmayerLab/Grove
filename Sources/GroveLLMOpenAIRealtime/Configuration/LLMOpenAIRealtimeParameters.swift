//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GeneratedOpenAIClient

/// Represents the parameters of OpenAIs Realtime LLMs.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct LLMOpenAIRealtimeParameters: Sendable {
    public enum ModelType: String, Sendable {
        // swiftlint:disable identifier_name

        case gpt4oRealtime = "gpt-4o-realtime-preview"
        case gpt4oRealtime_mini = "gpt-4o-mini-realtime-preview"
        case gptRealtime = "gpt-realtime"
        case gptRealtimeMini = "gpt-realtime-mini"
        case gptRealtime_2_1 = "gpt-realtime-2.1"
        case gptRealtime_2_1_mini = "gpt-realtime-2.1-mini"

        // swiftlint:enable identifier_name
    }

    /// Who configures the session once the socket is open.
    public enum SessionConfiguration: Sendable {
        /// The session sends its own `session.update` from these parameters.
        case client
        /// The session was pinned when its credential was minted; nothing is sent, so the server's choice stands.
        case server
    }

    /// The tool choice of the response requested after a tool call returned its output.
    public enum FollowUpToolChoice: String, Sendable {
        case auto
        /// Lets the model answer from the tool output without calling again, which a session that forces a
        /// tool on every turn needs to speak at all.
        case none
    }
    
    public enum OpenAIVoice: String, Sendable {
        /// Neutral and balanced
        case alloy
        /// Clear and precise
        case ash
        /// Melodic and smooth
        case ballad
        /// Warm and friendly
        case coral
        /// Resonant and deep
        case echo
        /// Calm and thoughtful
        case sage
        /// Bright and energetic
        case shimmer
        /// Versatile and expressive
        case verse
        case marin
        case cedar
        
        public static let `default`: OpenAIVoice = .alloy
    }
    
    /// Defaults of possible LLMs Realtime parameter settings.
    public enum Defaults {
        public static let defaultSystemPrompt: String = {
            String(localized: LocalizedStringResource("GROVE_LLM_OPENAI_REALTIME_SYSTEM_PROMPT", bundle: .atURL(from: .module)))
        }()
        public static let turnDetectionSettings: LLMRealtimeTurnDetectionSettings = .default
        public static let transcriptionSettings: LLMRealtimeTranscriptionSettings = .default
        public static let voice: OpenAIVoice = .default
    }


    /// The to-be-used OpenAI model.
    let modelType: String
    /// The to-be-used system prompt of the Realtime Session.
    let systemPrompt: String?
    /// Contains the LLMRealtimeTurnDetectionSettings. If set to nil, turn detection is disabled and requires explicit generation calls.
    let turnDetectionSettings: LLMRealtimeTurnDetectionSettings?
    /// Transcription settings to transcribe user audio input into text. If set, these automatically get appended to the LLMSession's `LLMContext`
    let transcriptionSettings: LLMRealtimeTranscriptionSettings?
    /// The voice to use for the assistant's audio output.
    let voice: OpenAIVoice?
    let sessionConfiguration: SessionConfiguration
    let followUpToolChoice: FollowUpToolChoice
    let overwritingAuthToken: RemoteLLMInferenceAuthToken?
    let overwritingServerUrl: URL?
    let transcriptGracePeriod: Duration?
    
    /// Creates the ``LLMOpenAIRealtimeParameters``.
    ///
    /// - Parameters:
    ///   - modelType: The OpenAI Realtime model to use (`gpt4oRealtime`, `gpt4oRealtime_mini`, or `gptRealtime`).
    ///   - systemPrompt: The system prompt to guide the model's behavior.
    ///   - turnDetectionSettings: Voice Activity Detection (VAD) settings to automatically detect when the user has finished speaking.
    ///                            Set to `nil` to disable automatic turn detection and require manual `endUserTurn()` calls.
    ///   - transcriptionSettings: Transcription settings to transcribe user audio input into text. If set, these automatically get appended to the LLMSession's `LLMContext`.
    ///   - voice: The voice to use for the assistant's audio output.
    ///   - sessionConfiguration: Whether the session configures itself or was pinned when its credential was minted.
    ///   - followUpToolChoice: The tool choice for the response requested after a tool call returned.
    ///   - overwritingAuthToken: Separate token that overrides the one defined within the ``LLMOpenAIRealtimePlatform``,
    ///                           for example an ephemeral client secret minted for this one session.
    ///   - overwritingServerUrl: Separate endpoint that overrides the platform's, for example the one the secret was minted for.
    ///   - transcriptGracePeriod: How long a tool call waits for the transcript of the turn it answers, so a tool can
    ///                            read the participant's words from the context. `nil` runs the tool right away.
    public init(
        modelType: ModelType,
        systemPrompt: String? = Defaults.defaultSystemPrompt,
        turnDetectionSettings: LLMRealtimeTurnDetectionSettings? = Defaults.turnDetectionSettings,
        transcriptionSettings: LLMRealtimeTranscriptionSettings? = Defaults.transcriptionSettings,
        voice: OpenAIVoice? = Defaults.voice,
        sessionConfiguration: SessionConfiguration = .client,
        followUpToolChoice: FollowUpToolChoice = .auto,
        overwritingAuthToken: RemoteLLMInferenceAuthToken? = nil,
        overwritingServerUrl: URL? = nil,
        transcriptGracePeriod: Duration? = nil
    ) {
        self.modelType = modelType.rawValue
        self.systemPrompt = systemPrompt
        self.turnDetectionSettings = turnDetectionSettings
        self.transcriptionSettings = transcriptionSettings
        self.voice = voice
        self.sessionConfiguration = sessionConfiguration
        self.followUpToolChoice = followUpToolChoice
        self.overwritingAuthToken = overwritingAuthToken
        self.overwritingServerUrl = overwritingServerUrl
        self.transcriptGracePeriod = transcriptGracePeriod
    }
}

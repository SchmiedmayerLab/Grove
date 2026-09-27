//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension LLMOpenAIRealtimeConnection {
    /// Both session.created and session.updated contain the effective transcription configuration.
    static func transcriptionEnabled(in event: [String: Any]) -> Bool {
        guard let session = event["session"] as? [String: Any] else {
            return false
        }
        if let audio = session["audio"] as? [String: Any], let input = audio["input"] as? [String: Any] {
            return input["transcription"] is [String: Any]
        }
        // Gateways using the beta interface keep the configuration directly on the session.
        return session["input_audio_transcription"] is [String: Any]
    }
}

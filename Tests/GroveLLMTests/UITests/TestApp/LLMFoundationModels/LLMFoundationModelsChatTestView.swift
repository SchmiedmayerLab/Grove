//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveChat
import GroveLLM
import GroveLLMFoundationModels
import SwiftUI


/// Runs a chat against Apple's on-device and Private Cloud Compute models.
///
/// Availability is checked before the chat is offered, since neither model is guaranteed to be there: the on-device
/// model needs an eligible device with Apple Intelligence turned on, and Private Cloud Compute additionally needs a
/// reachable system service.
@available(iOS 27, macOS 27, visionOS 27, *)
struct LLMFoundationModelsChatTestView: View {
    private let modelType: LLMFoundationModelsModelType

    @Environment(LLMFoundationModelsPlatform.self) private var platform
    @LLMSessionProvider<LLMFoundationModelsSchema> private var llm: LLMFoundationModelsSession
    @State private var muted = true

    var body: some View {
        Group {
            switch platform.availability(of: modelType) {
            case .available:
                LLMChatView(session: $llm)
                    .speak(llm.context.chat, muted: muted)
                    .speechToolbarButton(muted: $muted)
            case .unavailable(let reason):
                ContentUnavailableView(
                    "Model Unavailable",
                    systemImage: "apple.intelligence",
                    description: Text(Self.description(of: reason))
                )
                .accessibilityIdentifier("Model Unavailable")
            }
        }
        .navigationTitle(Self.title(of: modelType))
    }

    init(modelType: LLMFoundationModelsModelType) {
        self.modelType = modelType
        _llm = .init(
            schema: LLMFoundationModelsSchema(
                modelType: modelType,
                systemPrompt: "You're a helpful assistant that answers questions from users.",
                injectIntoContext: true
            )
        )
    }

    private static func title(of modelType: LLMFoundationModelsModelType) -> String {
        switch modelType {
        case .onDevice: "On-Device Model"
        case .privateCloudCompute: "Private Cloud Compute"
        }
    }

    private static func description(of reason: LLMFoundationModelsAvailability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: "This device does not support the model."
        case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in Settings to use this model."
        case .modelNotReady: "The model is not ready yet — assets may still be downloading."
        }
    }
}

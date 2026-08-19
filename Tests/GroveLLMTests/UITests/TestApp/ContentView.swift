//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveLLMAnthropic
import GroveLLMFoundationModels
import GroveLLMGemini
import GroveLLMOpenAI
import SwiftUI


struct ContentView: View {
    var body: some View {
        Form {
            ForEach(Test.allCases) { test in
                NavigationLink(test.rawValue) {
                    test.view
                }
            }
        }
        .formStyle(.grouped)
        .overlay(alignment: .bottom) {
            if FeatureFlags.liveAPIToken != nil {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("Live Provider Configured")
                    .accessibilityHidden(false)
            }
        }
    }
}


extension ContentView {
    enum Test: String, CaseIterable, Identifiable {
        case llmMockChat = "LLMMock Chat"
        case llmOpenAI = "LLMOpenAI"
        case llmLocal = "LLMLocal"
        case llmOpenAIRealtime = "LLMOpenAIRealtime"
        case llmAnthropic = "LLMAnthropic"
        case llmGemini = "LLMGemini"
        case llmFoundationModelsOnDevice = "LLMFoundationModels On-Device"
        case llmFoundationModelsCloud = "LLMFoundationModels Private Cloud"
        
        var id: some Hashable {
            rawValue
        }
        
        @MainActor @ViewBuilder var view: some View {
            switch self {
            case .llmMockChat:
                LLMMockChatTestView()
            case .llmOpenAI:
                LLMOpenAILikeChatTestView<OpenAIPlatformDefinition>(model: .gpt4o)
            case .llmLocal:
                LLMLocalTestView()
            case .llmOpenAIRealtime:
                LLMOpenAIRealtimeTestView()
            case .llmAnthropic:
                LLMOpenAILikeChatTestView<AnthropicPlatformDefinition>(model: .opus4_6)
            case .llmGemini:
                LLMOpenAILikeChatTestView<GeminiPlatformDefinition>(model: .gemini2_5_pro)
            case .llmFoundationModelsOnDevice:
                if #available(iOS 27, macOS 27, visionOS 27, *) {
                    LLMFoundationModelsChatTestView(modelType: .onDevice)
                }
            case .llmFoundationModelsCloud:
                if #available(iOS 27, macOS 27, visionOS 27, *) {
                    LLMFoundationModelsChatTestView(modelType: .privateCloudCompute)
                }
            }
        }
    }
}

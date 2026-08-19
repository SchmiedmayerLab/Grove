//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Grove
import GroveLLM
import GroveLLMAnthropic
import GroveLLMFoundationModels
import GroveLLMGemini
import GroveLLMLocal
import GroveLLMOpenAI
import GroveLLMOpenAIRealtime


class TestAppDelegate: GroveAppDelegate {
    override var configuration: Configuration {
        Configuration {
            LLMRunner {
                LLMMockPlatform()
                LLMOpenAIPlatform(configuration: .init(
                    authToken: .keychain(for: LLMOpenAIPlatform.self)
                ))
                LLMAnthropicPlatform(configuration: .init(
                    authToken: .keychain(for: LLMAnthropicPlatform.self)
                ))
                LLMGeminiPlatform(configuration: .init(
                    authToken: .keychain(for: LLMGeminiPlatform.self)
                ))
                LLMLocalPlatform()   // Note: not compatible with the simulator; runs on a device.
                if #available(iOS 27, macOS 27, visionOS 27, *) {
                    LLMFoundationModelsPlatform()
                }
                LLMOpenAIRealtimePlatform(configuration: .init(
                    authToken: .keychain(for: LLMOpenAIPlatform.self)
                ))
            }
        }
    }
}

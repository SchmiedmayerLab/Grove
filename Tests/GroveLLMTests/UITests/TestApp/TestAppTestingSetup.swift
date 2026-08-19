//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Security
import GroveKeychainStorage
import GroveLLMAnthropic
import GroveLLMGemini
import GroveLLMOpenAI
import SwiftUI


private struct TestAppTestingSetup: ViewModifier {
    @Environment(KeychainStorage.self) var keychain
    @Environment(LLMOpenAIPlatform.self) var openAIPlatform
    @Environment(LLMAnthropicPlatform.self) var anthropicPlatform
    @Environment(LLMGeminiPlatform.self) var geminiPlatform
    @AppStorage(StorageKeys.localOnboardingFlowComplete) private var completedLocalOnboardingFlow = false

    
    func body(content: Content) -> some View {
        content
            .task {
                if FeatureFlags.resetSecureStorage {
                    try? openAIPlatform.clearApiKeyCredentials(in: keychain)
                    try? anthropicPlatform.clearApiKeyCredentials(in: keychain)
                    try? geminiPlatform.clearApiKeyCredentials(in: keychain)
                }
                // A live UI test hands the token to the app rather than typing it through the interface, so it
                // never reaches a screenshot. Seeding the keychain is what the onboarding would have done.
                if let liveToken = FeatureFlags.liveAPIToken {
                    try? keychain.store(
                        Credentials(username: "\(OpenAIPlatformDefinition.platformName)_Token", password: liveToken),
                        for: .for(OpenAIPlatformDefinition.self)
                    )
                }
                if FeatureFlags.showOnboarding {
                    completedLocalOnboardingFlow = false
                }
            }
    }
}


extension View {
    func testingSetup() -> some View {
        self.modifier(TestAppTestingSetup())
    }
}

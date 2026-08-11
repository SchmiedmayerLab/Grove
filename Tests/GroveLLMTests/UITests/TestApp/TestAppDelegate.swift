//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable all

import Foundation
import GeneratedOpenAIClient
import Grove
#if os(iOS)
import FirebaseAuth
import FirebaseFirestore
import GroveAccount
import GroveFirebaseAccount
import GroveFirebaseAccountStorage
#endif
import GroveKeychainStorage
import GroveLLM
import GroveLLMAnthropic
import GroveLLMGemini
import GroveLLMLocal
import GroveLLMOpenAI
import GroveLLMOpenAIRealtime


class TestAppDelegate: GroveAppDelegate {
    // Used for production-ready setup including TLS traffic to the fog node
    nonisolated private static var caCertificateUrl: URL? {
        guard let url = Bundle.main.url(forResource: "ca", withExtension: "crt") else {
            fatalError("CA Certificate not found!")
        }
        
        return url
    }
    
    override var configuration: Configuration {
        Configuration {
            // As GroveAccount, GroveFirebase and the firebase-ios-sdk currently don't support visionOS and macOS, perform fog node token authentication only on iOS
            #if os(iOS)
            AccountConfiguration(
                service: FirebaseAccountService(providers: [.emailAndPassword], emulatorSettings: (host: "localhost", port: 9099)),
                storageProvider: FirestoreAccountStorage(storeIn: Firestore.firestore().collection("users")),
                configuration: [
                    .requires(\.userId)
                ]
            )
            #endif
            
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
                LLMLocalPlatform() // Note: Grove LLM Local is not compatible with simulators.
                LLMOpenAIRealtimePlatform(
                    configuration: .init(
                        authToken: .keychain(for: LLMOpenAIPlatform.self)
                    )
                )
            }
        }
    }
}

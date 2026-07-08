//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziKeychainStorage


/// Constants used throughout the `SpeziLLMFog` target.
@available(iOS 17, macOS 14, visionOS 1, *)
public enum LLMFogConstants {
    /// Default credentials username of `SpeziLLMFog` .
    public static let credentialsUsername = "LLM_Fog_Token"
}

/// The credentials tag of the fog auth token in the secure enclave.
@available(iOS 17, macOS 14, visionOS 1, *)
extension CredentialsTag {
    /// Default `CredentialsTag` of the SpeziLLMFog auth token.
    public static let fogAuthToken = CredentialsTag.genericPassword(forService: "spezifog.edu")
}

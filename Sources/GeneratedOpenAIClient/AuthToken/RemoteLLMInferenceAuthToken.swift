//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Security)
public import struct GroveKeychainStorage.CredentialsTag
#endif


/// The type of auth token for remote LLM services, such as the OpenAI or Fog layer.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum RemoteLLMInferenceAuthToken: Sendable {
    /// No auth token.
    case none
    /// Constant auth token that is static during the lifetime of the ``RemoteLLMInferenceAuthToken``.
    case constant(String)
    #if canImport(Security)
    /// Auth token persisted in the keychain tagged with the `CredentialsTag` and username, dynamically read from the keychain upon every request.
    ///
    /// Only where the platform has a Keychain. Elsewhere, supply the token with ``constant(_:)`` or ``closure(_:)``.
    case keychain(tag: CredentialsTag, username: String)
    #endif
    /// Auth token dynamically produced by a closure, reevaluated upon every request.
    case closure(@Sendable () async -> String?)
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The two declarations below are mutually exclusive; the rule counts them as if both were in the file.
// swiftlint:disable file_types_order

#if !canImport(Security)


/// Stands in for the Keychain on platforms that have none.
///
/// Uninhabited on purpose: the only value of `LLMCredentialStorage?` these platforms can produce is `nil`, which
/// keeps every signature that passes a credential store around compiling without pretending a Keychain exists.
/// A server supplies its token through ``RemoteLLMInferenceAuthToken/constant(_:)`` or
/// ``RemoteLLMInferenceAuthToken/closure(_:)`` instead — read from the environment or a secrets manager.
@available(iOS 18, macOS 15, watchOS 11, *)
package enum LLMCredentialStorage: Sendable {}
#else
package import GroveKeychainStorage


/// The store a keychain-backed auth token is read from.
@available(iOS 18, macOS 15, watchOS 11, *)
package typealias LLMCredentialStorage = KeychainStorage
#endif

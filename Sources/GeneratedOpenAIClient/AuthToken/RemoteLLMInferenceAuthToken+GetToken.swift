//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import GroveKeychainStorage


@available(iOS 18, macOS 15, watchOS 11, *)
extension RemoteLLMInferenceAuthToken {
    package func getToken(keychainStorage: KeychainStorage?) async throws -> String? {
        switch self {
        case .none:
            return nil

        case .constant(let string):
            return string

        case let .keychain(credentialsTag, username):  // extract the keychain token on every request
            let credential: Credentials?

            do {
                credential = try keychainStorage?.retrieveCredentials(
                    withUsername: username,
                    for: credentialsTag
                )
            } catch {
                throw RemoteLLMInferenceAuthTokenError.keychainAccessError(error)
            }

            guard let credentialToken = credential?.password else {
                throw RemoteLLMInferenceAuthTokenError.noTokenInKeychain
            }

            return credentialToken

        case .closure(let tokenClosure):
            return await tokenClosure()
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
package import Foundation


/// Incremental SHA-1 for the checksum required by FHIR R4 `Attachment.hash`.
/// This is not an authorization or signature primitive.
package struct AttachmentHasher {
    private var hasher = Insecure.SHA1()

    package init() {}

    package mutating func update(_ bytes: Data) {
        hasher.update(data: bytes)
    }

    package func finalize() -> Data {
        Data(hasher.finalize())
    }
}

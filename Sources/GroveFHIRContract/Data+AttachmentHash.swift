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


extension Data {
    /// The SHA-1 digest of these bytes: what FHIR R4 states, base64-encoded, as an `Attachment.hash`.
    ///
    /// Every adapter that attaches a payload and the graph validator that checks it compute the hash here, so the
    /// adapters need no cryptography module of their own, on Linux included.
    package var attachmentSHA1: Data {
        Data(Insecure.SHA1.hash(data: self))
    }
}

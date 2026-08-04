//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import UniformTypeIdentifiers


/// Errors thrown while interacting with FHIR attachment types.
enum FHIRAttachmentError: Error, Equatable {
    /// The attachment does not have a valid MIME type.
    case missingMimeType

    /// The attachment does not contain any data.
    case noData

    /// The text data couldn't be decoded using UTF-8 encoding.
    case textDecodingFailed

    /// The data couldn't be parsed as a valid PDF document.
    case pdfParsingFailed

    /// The content type is not supported by any available extractor.
    case unsupportedContentType(UTType)
}


/// Uniform interface for FHIR attachment types.
protocol FHIRAttachment: Sendable/*, CustomDebugStringConvertible*/ {
    var _contentTypeString: String? { get set }
    var _base64String: String? { get set }
}


extension FHIRAttachment {
    /// Best effort parsing of the MIME type of the attachment.
    /// Represents the content type of the attachment data (e.g., `text/plain`, `application/pdf`, etc).
    var mimeType: UTType? {
        get {
            _contentTypeString.flatMap {
                UTType(mimeType: $0)
            }
        }
        set {
            _contentTypeString = newValue?.preferredMIMEType // TODO what if preferredMIMEType is nil??
        }
    }

    /// Convenience property to get the Base64 string representation of the attachment data.
    func data() -> Data? {
        _base64String.flatMap {
            Data(base64Encoded: $0)
        }
    }

    /// Updates the FHIR attachment's contents.
    ///
    /// This function completely replaces the attachment's contents with the `data` and `mimeType` inputs.
    ///
    /// - Important: This function will unconditionally base64-encode its `data` input before writing it into the attachment
    ///
    /// - parameter data: The new contents for the attachments. Will be base64 encoded by this function.
    mutating func setData(_ data: Data, mimeType: UTType) {
        self._base64String = data.base64EncodedString()
        self.mimeType = mimeType
    }
}

#endif

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import GroveFoundation


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
    case unsupportedContentType(MIMEType)
}


/// Uniform interface for FHIR attachment types.
protocol FHIRAttachment: Sendable {
    // swiftlint:disable identifier_name
    var _contentTypeString: String? { get set }
    var _base64String: String? { get set }
    // swiftlint:enable identifier_name
}


extension FHIRAttachment {
    /// The media type of the attachment data (e.g. `text/plain`, `application/pdf`).
    ///
    /// Carried through verbatim: a type the platform has no `UTType` for is still the type FHIR stated,
    /// so it survives a read and is written back exactly as it came.
    var mimeType: MIMEType? {
        get {
            // An empty `contentType` states nothing, so it reads as absent rather than as a blank type.
            _contentTypeString.flatMap { $0.isEmpty ? nil : MIMEType(rawValue: $0) }
        }
        set {
            _contentTypeString = newValue?.rawValue
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
    mutating func setData(_ data: Data, mimeType: MIMEType) {
        self._base64String = data.base64EncodedString()
        self.mimeType = mimeType
    }
    
    mutating func unsafelySetPlainTextDataSkippingBase64Encode(_ string: String) {
        self._base64String = string
        self.mimeType = .plainText
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

private import ModelsDSTU2
private import ModelsR4
private import UniformTypeIdentifiers


extension FHIRResource {
    struct StringificationOptions {
        /// Whether the result of the stringification should be stored as base64-encoded data in the attachment's underlying`Base64Binary`.
        let skipBase64EncodeIfPossible: Bool
        /// The default set of content extractors. PDF extraction relies on PDFKit, which is unavailable
        /// on watchOS, so it is only included where PDFKit can be imported.
        let contentExtractors: [any FHIRAttachmentContentExtractor]
        
        init(
            skipBase64EncodeIfPossible: Bool = false,
            contentExtractors: [any FHIRAttachmentContentExtractor] = [.text, .pdf]
        ) {
            self.skipBase64EncodeIfPossible = skipBase64EncodeIfPossible
            self.contentExtractors = contentExtractors
        }
        
        fileprivate func extractor(for contentType: UTType) -> (any FHIRAttachmentContentExtractor)? {
            contentExtractors.first { $0.isCompatible(with: contentType) }
        }
    }
    
    /// Best effort function to transform the base64 data representation of a FHIR attachment to a string-based representation of the data type.
    ///
    /// This funcationality is especially useful if the data content is inspected for debug purposes or passing it ot a LLM component.
    ///
    /// - parameter skipBase64EncodeIfPossible: Whether the stringification step should skip base64-encoding the stringification result
    ///     when storing it into the attachment's underlying`Base64Binary`.
    ///     Defaults to `false`, in order to produce FHIR-compliant output. Set to `true` to produce output that technically isn't FHIR-compliant
    ///     (because the spec requires `Base64Binary` to contain base64-encoded data), but is more easily ingestable by LLM pipelines.
    /// - parameter contentExtractors: The extractors used to turn an attachment's content type into text.
    ///     Defaults to text and, where PDFKit is available, PDF.
    public mutating func stringifyAttachments(
        skipBase64EncodeIfPossible: Bool = false,
        contentExtractors: [any FHIRAttachmentContentExtractor] = [.text, .pdf]
    ) throws {
        let options = StringificationOptions(
            skipBase64EncodeIfPossible: skipBase64EncodeIfPossible,
            contentExtractors: contentExtractors
        )
        try stringifyAttachments(using: options)
    }

    mutating func stringifyAttachments(using options: StringificationOptions) throws {
        switch versionedResource {
        case .r4(let resource):
            guard var docRef = resource as? ModelsR4.DocumentReference else {
                return
            }
            for idx in docRef.content.indices {
                try docRef.content[idx].attachment.stringify(using: options)
            }
            self = try .init(
                versionedResource: .r4(docRef),
                displayName: self.displayName,
                identitySource: nonLogicalIdentitySource
            )
        case .dstu2(let resource):
            guard var docRef = resource as? ModelsDSTU2.DocumentReference else {
                return
            }
            for idx in docRef.content.indices {
                try docRef.content[idx].attachment.stringify(using: options)
            }
            self = try .init(
                versionedResource: .dstu2(docRef),
                displayName: self.displayName,
                identitySource: nonLogicalIdentitySource
            )
        }
    }
}


extension FHIRAttachment {
    /// Transforms a FHIR attachment's base64-encoded data into human-readable text.
    ///
    /// This method extracts text content from various attachment formats (PDF, text files, etc.)
    /// based on their MIME type and replaces the original binary content with the extracted text,
    /// re-encoded as base64 to maintain FHIR data structure compatibility.
    ///
    /// - Parameter attachment: The FHIR attachment to transform.
    /// - Throws: `FHIRAttachmentError` if the transformation fails for any reason,
    ///           such as missing MIME type, invalid base64 data, or unsupported content type.
    mutating func stringify(
        using options: FHIRResource.StringificationOptions
    ) throws {
        let (newType, newContent) = try _stringify(using: options)
        if options.skipBase64EncodeIfPossible, let string = String(data: newContent, encoding: .utf8) {
            unsafelySetPlainTextDataSkippingBase64Encode(string)
        } else {
            setData(newContent, mimeType: newType)
        }
    }
    
    private func _stringify(using options: FHIRResource.StringificationOptions) throws -> (UTType, Data) {
        guard let contentType = self.mimeType else {
            throw FHIRAttachmentError.missingMimeType
        }
        guard let extractor = options.extractor(for: contentType) else {
            throw FHIRAttachmentError.unsupportedContentType(contentType)
        }
        guard let data = self.data() else {
            throw FHIRAttachmentError.noData
        }
        return try extractor.extractContent(from: data)
    }
}

#endif

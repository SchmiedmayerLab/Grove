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


extension FHIRResource {
    /// Best effort function to transform the base64 data representation of a FHIR attachment to a string-based representation of the data type.
    ///
    /// This funcationality is especially useful if the data content is inspected for debug purposes or passing it ot a LLM component.
    public mutating func stringifyAttachments() throws {
        try stringifyAttachments(using: FHIRAttachmentService())
    }

    mutating func stringifyAttachments(using service: FHIRAttachmentService) throws {
        switch versionedResource {
        case .r4(let resource):
            guard var docRef = resource as? ModelsR4.DocumentReference else {
                return
            }
            for idx in docRef.content.indices {
                try service.stringify(attachment: &docRef.content[idx].attachment)
            }
            self = .init(versionedResource: .r4(docRef), displayName: self.displayName)
        case .dstu2(let resource):
            guard var docRef = resource as? ModelsDSTU2.DocumentReference else {
                return
            }
            for idx in docRef.content.indices {
                try service.stringify(attachment: &docRef.content[idx].attachment)
            }
            self = .init(versionedResource: .dstu2(docRef), displayName: self.displayName)
        }
    }
}

#endif

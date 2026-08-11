//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import ModelsDSTU2
import UniformTypeIdentifiers


extension ModelsDSTU2.Attachment: FHIRAttachment {
    var mimeType: UTType? {
        guard let mimeTypeString = contentType?.value?.string,
              !mimeTypeString.isEmpty else {
            return nil
        }
        return UTType(mimeType: mimeTypeString)
    }
    
    var base64String: String? {
        data?.value?.dataString
    }

    mutating func setData(from string: String) {
        data = FHIRPrimitive(ModelsDSTU2.Base64Binary(string))
    }
}

#endif

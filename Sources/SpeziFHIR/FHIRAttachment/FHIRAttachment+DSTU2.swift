//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import ModelsDSTU2
import UniformTypeIdentifiers


extension ModelsDSTU2.Attachment: FHIRAttachment {
    var _contentTypeString: String? {
        get {
            contentType?.value?.string
        }
        set {
            contentType = newValue?.asFHIRStringPrimitive()
        }
    }
    
    var _base64String: String? {
        get {
            data?.value?.dataString
        }
        set {
            data = newValue.map {
                FHIRPrimitive(ModelsDSTU2::Base64Binary($0))
            }
        }
    }
}

#endif

//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UniformTypeIdentifiers)

import ModelsR4
import UniformTypeIdentifiers


extension ModelsR4.Attachment: FHIRAttachment {
    var _contentTypeString: String? { // swiftlint:disable:this identifier_name
        get {
            contentType?.value?.string
        }
        set {
            contentType = newValue?.asFHIRStringPrimitive()
        }
    }
    
    var _base64String: String? { // swiftlint:disable:this identifier_name
        get {
            self.data?.value?.dataString
        }
        set {
            self.data = newValue.map {
                FHIRPrimitive(ModelsR4::Base64Binary($0))
            }
        }
    }
}

#endif

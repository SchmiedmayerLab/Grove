//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


extension RegisteredRecordingFormat {
    /// Whether the registry admits `contentType` for this format: one of the media types it names, or, for a format whose
    /// media type the source declares, any value its pattern matches.
    package func admitsContentType(_ contentType: String) -> Bool {
        guard let declared = sourceDeclaredContentType else {
            return registeredContentTypes.contains(contentType)
        }
        // The registry's pattern is anchored at both ends, so a match covers the whole value.
        return contentType.range(of: declared.pattern, options: .regularExpression) != nil
    }

    /// The media type a document of this format states for a payload whose source declares `declared`.
    ///
    /// A format whose media types the registry names states its one exact type whatever the source declares. A format whose
    /// media type the source declares states `declared` in lowercase when the registry's pattern admits it, and the
    /// registry's fallback otherwise, so a missing or malformed declaration never makes the document invalid.
    package func statedContentType(declared: String?) -> String? {
        guard let sourceDeclared = sourceDeclaredContentType else {
            return registeredContentType
        }
        guard let lowercased = declared?.lowercased(), admitsContentType(lowercased) else {
            return sourceDeclared.fallback
        }
        return lowercased
    }
}

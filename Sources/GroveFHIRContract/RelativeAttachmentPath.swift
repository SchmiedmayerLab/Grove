//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Whether `path` is an unescaped relative reference without empty or dot segments, a query or a fragment, which a
/// deployment resolves against its own storage root.
package func isRelativeAttachmentPath(_ path: String) -> Bool {
    guard !path.isEmpty,
          !path.hasPrefix("/"),
          !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
              $0.isEmpty || $0 == "." || $0 == ".."
          }),
          let components = URLComponents(string: path),
          components.scheme == nil,
          components.host == nil,
          components.query == nil,
          components.fragment == nil,
          components.percentEncodedPath == path,
          components.path == path else {
        return false
    }
    return true
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFoundation


/// An image or file the user staged for the next message, with an identity of its own so that
/// removal targets the right item even while insertions and removals animate.
@available(iOS 18, macOS 15, watchOS 11, *)
struct DraftAttachment: Identifiable {
    /// What the user staged.
    enum Content {
        case image(PlatformImage)
        case file(ChatEntity.Content.File)
    }

    let id = UUID()
    /// The photo library identifier the image was loaded from, when it has one; guards against
    /// staging the same photo twice when picker selections overlap.
    let itemIdentifier: String?
    let content: Content
}

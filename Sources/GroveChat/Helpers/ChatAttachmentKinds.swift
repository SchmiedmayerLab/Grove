//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import SwiftUI


/// What a chat lets the user attach to a message.
///
/// A chat that answers questions about a photo wants the photo library; a focused, task-specific chat may want no
/// attach button at all. Which kinds are offered is the app's decision rather than a fixed part of the composer.
///
/// An `OptionSet`, so a further kind can be added without changing the shape of
/// ``SwiftUICore/View/chatAttachments(_:)`` or of any call to it.
///
/// - Note: ``camera`` needs an `NSCameraUsageDescription` in the app that offers it, and is only available where
///     there is a camera to reach — it is left out of the menu on macOS, visionOS and the Simulator.
///
/// ## Topics
///
/// ### Kinds
/// - ``photoLibrary``
/// - ``camera``
/// - ``files``
/// - ``all``
///
/// ### Choosing what to offer
/// - ``SwiftUICore/View/chatAttachments(_:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct ChatAttachmentKinds: OptionSet, Hashable, Sendable {
    /// Images picked from the user's photo library.
    public static let photoLibrary = Self(rawValue: 1 << 0)
    /// A photo taken with the camera.
    public static let camera = Self(rawValue: 1 << 1)
    /// Documents picked from the file browser.
    public static let files = Self(rawValue: 1 << 2)

    /// Everything the composer offers.
    public static let all: Self = [.photoLibrary, .camera, .files]

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension EnvironmentValues {
    /// What the composer lets the user attach.
    @Entry var chatAttachmentKinds: ChatAttachmentKinds = .photoLibrary
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension View {
    /// Chooses what the user may attach to a message.
    ///
    /// Pass `[]` to take the attach button away entirely.
    ///
    /// ### Usage
    ///
    /// ```swift
    /// ChatView($chat)
    ///     .chatAttachments(.photoLibrary)
    /// ```
    ///
    /// - Parameter kinds: The kinds of attachment to offer. Defaults to the photo library.
    public func chatAttachments(_ kinds: ChatAttachmentKinds) -> some View {
        environment(\.chatAttachmentKinds, kinds)
    }
}

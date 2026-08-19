//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import SwiftUI


/// The platform's native image type: `UIImage` on UIKit platforms, `NSImage` on macOS.
#if canImport(UIKit)
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias PlatformImage = NSImage
#else
#error("Unsupported Platform")
#endif


#if canImport(AppKit)

/// `UIImage` has this; `NSImage` doesn't.
@available(iOS 18, macOS 15, watchOS 11, *)
extension NSImage {
    func pngData() -> Data? {
        tiffRepresentation
            .flatMap { NSBitmapImageRep(data: $0) }?
            .representation(using: .png, properties: [:])
    }
}

#endif


@available(iOS 18, macOS 15, watchOS 11, *)
extension Image {
    init(platformImage image: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #elseif canImport(AppKit)
        self.init(nsImage: image)
        #endif
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.Image {
    /// The image decoded without touching the network: in-memory images directly, `data:` URLs synchronously.
    ///
    /// `nil` for remote URLs, which must be loaded asynchronously.
    var locallyLoadedImage: PlatformImage? {
        switch self {
        case .image(let image):
            image
        case .url(let url) where url.scheme == "data":
            (try? Data(contentsOf: url)).flatMap(PlatformImage.init(data:))
        case .url:
            nil
        }
    }
}

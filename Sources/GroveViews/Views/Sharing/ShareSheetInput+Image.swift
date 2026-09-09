//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS) || os(visionOS)
import LinkPresentation
public import UIKit


/// Hands a picture to the share sheet with the metadata its header needs to preview it.
///
/// A bare image or item provider leaves the header with the app's icon and no title; an item source with
/// link metadata gets the picture's own thumbnail there.
private final class ImageActivityItemSource: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}


extension ShareSheetInput {
    /// Creates a new `ShareSheetInput` for a picture, previewed in the sheet's header under `title`.
    public init(image: UIImage, title: String) {
        self.init(verbatim: ImageActivityItemSource(image: image, title: title), id: ObjectIdentifier.init)
    }
}
#endif

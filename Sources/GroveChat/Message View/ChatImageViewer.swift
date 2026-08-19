//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


/// Shows a message's images full-screen, starting from the one that was tapped.
///
/// A message lays its images out small enough to sit in the conversation, which is too small to actually look at
/// them. Opening them here gives them the whole screen, pages between them when a message carries several, and
/// offers the one on screen to the share sheet.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ChatImageViewer: View {
    let images: [ChatEntity.Content.Image]

    @State private var selection: Int
    @State private var shareSheetInput: ShareSheetInput?

    private var shareableImage: ShareSheetInput? {
        guard images.indices.contains(selection) else {
            return nil
        }
        switch images[selection] {
        case .image(let image):
            return ShareSheetInput(image)
        case .url(let url):
            return ShareSheetInput(url)
        }
    }

    var body: some View {
        NavigationStack {
            pages
                .background(.black)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        DismissButton()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            shareSheetInput = shareableImage
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityLabel(Text("SHARE_IMAGE", bundle: .module))
                        }
                        .disabled(shareableImage == nil)
                    }
                }
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationTitle(pageDescription)
        }
        .shareSheet(item: $shareSheetInput)
    }

    /// The images themselves, paged where there is more than one to page between.
    @ViewBuilder private var pages: some View {
        #if os(iOS) || os(visionOS)
        TabView(selection: $selection) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                zoomableImage(image)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
        #else
        // No paging control on macOS; the arrow keys move through the images instead.
        zoomableImage(images[selection])
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .left: selection = max(0, selection - 1)
                case .right: selection = min(images.count - 1, selection + 1)
                default: break
                }
            }
        #endif
    }

    /// Reads as "3 of 7" only when there is more than one image.
    private var pageDescription: Text {
        guard images.count > 1 else {
            return Text("IMAGE", bundle: .module)
        }
        return Text("IMAGE_N_OF_M \(selection + 1) \(images.count)", bundle: .module)
    }

    init(images: [ChatEntity.Content.Image], startingAt index: Int = 0) {
        self.images = images
        self._selection = State(initialValue: images.indices.contains(index) ? index : 0)
    }

    @ViewBuilder
    private func zoomableImage(_ image: ChatEntity.Content.Image) -> some View {
        ScrollView([.horizontal, .vertical]) {
            PlainMessageView.AttachedImagesView.imageContent(for: image, fillingTile: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

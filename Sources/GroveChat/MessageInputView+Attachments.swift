//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif


@available(iOS 26, macOS 26, visionOS 26, *)
extension MessageInputView {
    @ViewBuilder var attachButton: some View {
        #if canImport(PhotosUI) && !os(watchOS)
        if attachmentKinds == .photoLibrary {
            PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                attachButtonLabel
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        } else if !offeredAttachmentKinds.isEmpty {
            Menu {
                attachmentMenuItems
            } label: {
                attachButtonLabel
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        #endif
    }

    #if canImport(PhotosUI) && !os(watchOS)
    nonisolated var attachButtonLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 17, weight: .medium))
            .accessibilityLabel(Text("ATTACH_FILES", bundle: .module))
            .foregroundStyle(.secondary)
            .frame(width: Self.controlSize, height: Self.controlSize)
    }

    /// What the composer can actually offer here: the camera drops out where there is none to reach.
    private var offeredAttachmentKinds: ChatAttachmentKinds {
        var kinds = attachmentKinds
        #if !os(iOS)
        kinds.remove(.camera)
        #else
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            kinds.remove(.camera)
        }
        #endif
        return kinds
    }

    @ViewBuilder private var attachmentMenuItems: some View {
        if offeredAttachmentKinds.contains(.photoLibrary) {
            Button {
                isShowingPhotoPicker = true
            } label: {
                Label {
                    Text("ATTACH_PHOTO_LIBRARY", bundle: .module)
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
            }
        }
        #if os(iOS)
        if offeredAttachmentKinds.contains(.camera) {
            Button {
                isShowingCamera = true
            } label: {
                Label {
                    Text("ATTACH_CAMERA", bundle: .module)
                } icon: {
                    Image(systemName: "camera")
                }
            }
        }
        #endif
        if offeredAttachmentKinds.contains(.files) {
            Button {
                isShowingFileImporter = true
            } label: {
                Label {
                    Text("ATTACH_FILES_MENU", bundle: .module)
                } icon: {
                    Image(systemName: "folder")
                }
            }
        }
    }
    #endif
}


@available(iOS 26, macOS 26, visionOS 26, *)
extension MessageInputView {
    var attachmentPreviews: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let attachmentFailure {
                Label(attachmentFailure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !attachments.isEmpty {
                stagedRow
            }
        }
    }

    private var stagedRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    stagedPreview(for: attachment)
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.smooth(duration: 0.25)) {
                                    attachments.removeAll { $0.id == attachment.id }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .accessibilityLabel(Text("REMOVE_ATTACHMENT", bundle: .module))
                            }
                            .buttonStyle(.plain)
                            .padding(3)
                        }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .frame(height: 60)
    }
}


#if canImport(PhotosUI) && !os(watchOS)
@available(iOS 26, macOS 26, visionOS 26, *)
extension MessageInputView {
    /// Takes app-owned copies of the picked files and stages them.
    func stageFiles(from result: Result<[URL], any Error>) {
        guard case .success(let urls) = result else {
            return
        }
        var staged: [Attachment] = []
        var failure: String?
        let store = attachmentStore ?? ChatAttachmentStore.fallback
        for url in urls {
            do {
                staged.append(Attachment(itemIdentifier: nil, content: .file(try store.store(fileAt: url))))
            } catch {
                // Reporting the first refusal is enough; a picked file that vanished with no reason given is the
                // part worth avoiding.
                failure = failure ?? (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        withAnimation(.smooth(duration: 0.25)) {
            attachmentFailure = failure
            attachments.append(contentsOf: staged)
        }
    }

    /// What a staged attachment looks like before it is sent: the photo itself, or the file's kind and name.
    @ViewBuilder
    private func stagedPreview(for attachment: Attachment) -> some View {
        switch attachment.content {
        case .image(let image):
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
        case .file(let file):
            VStack(spacing: 2) {
                Image(systemName: file.symbolName)
                    .font(.title3)
                Text(file.name)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
            .background(.quaternary.opacity(0.6))
        }
    }
}
#endif

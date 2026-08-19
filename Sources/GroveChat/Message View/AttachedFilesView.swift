//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(QuickLook) && !os(watchOS)
import QuickLook
#endif
import SwiftUI
import UniformTypeIdentifiers


/// Lays the files attached to a message out as chips.
///
/// A file has nothing to show the way an image does, so it is named rather than rendered: an icon for its kind, its
/// name, and how big it is. Tapping one opens it in the system's own preview, which handles every format Quick Look
/// knows without this package learning any of them.
@available(iOS 18, macOS 15, watchOS 11, *)
struct AttachedFilesView: View {
    let files: [ChatEntity.Content.File]

    @State private var previewedFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(files, id: \.url) { file in
                Button {
                    previewedFile = file.url
                } label: {
                    chip(for: file)
                }
                .buttonStyle(.plain)
            }
        }
        #if canImport(QuickLook) && !os(watchOS)
        .quickLookPreview($previewedFile, in: files.map(\.url))
        #endif
    }

    private func chip(for file: ChatEntity.Content.File) -> some View {
        HStack(spacing: 10) {
            Image(systemName: file.symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let description = file.sizeDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ChatEntity.Content.File {
    /// The SF Symbol standing in for the file's kind.
    ///
    /// Quick Look draws a real document icon in the preview; a chip only needs enough to tell a PDF from a
    /// spreadsheet at a glance.
    var symbolName: String {
        guard let identifier = contentTypeIdentifier, let type = UTType(identifier) else {
            return "document"
        }
        return switch type {
        case _ where type.conforms(to: .pdf): "document.fill"
        case _ where type.conforms(to: .spreadsheet): "tablecells"
        case _ where type.conforms(to: .presentation): "rectangle.on.rectangle"
        case _ where type.conforms(to: .image): "photo"
        case _ where type.conforms(to: .movie), _ where type.conforms(to: .audio): "waveform"
        case _ where type.conforms(to: .archive): "doc.zipper"
        case _ where type.conforms(to: .sourceCode): "chevron.left.forwardslash.chevron.right"
        case _ where type.conforms(to: .text): "doc.text"
        default: "document"
        }
    }

    /// How large the file is, ready to show, or `nil` when that cannot be read.
    var sizeDescription: String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return size.formatted(.byteCount(style: .file))
    }
}

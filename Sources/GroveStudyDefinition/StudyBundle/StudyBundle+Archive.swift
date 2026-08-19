//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// The file extension of a compressed study bundle archive.
    public static let archiveFileExtension = "\(fileExtension).tar.zst"

    /// Far beyond any real study bundle, but a bound on what a hostile archive can allocate.
    private static let maximumArchiveContentSize = 1 << 30

    /// Extracts the zstd-compressed tar archive at `archiveUrl` into `bundleUrl`, replacing any
    /// previous contents, and opens the bundle.
    public static func unarchive(_ archiveUrl: URL, to bundleUrl: URL) throws -> StudyBundle {
        let tar = try Zstd.decompress(Data(contentsOf: archiveUrl), maximumDecompressedSize: maximumArchiveContentSize)
        let fileManager = FileManager.default
        // Extract into a staging sibling first, so a malformed archive cannot destroy a
        // previously extracted bundle.
        let stagingUrl = bundleUrl.deletingLastPathComponent()
            .appending(path: "\(bundleUrl.lastPathComponent).staging-\(UUID().uuidString)")
        defer {
            try? fileManager.removeItem(at: stagingUrl)
        }
        try write(Tar.entries(in: tar), to: stagingUrl)
        if fileManager.itemExists(at: bundleUrl) {
            try fileManager.removeItem(at: bundleUrl)
        }
        try fileManager.moveItem(at: stagingUrl, to: bundleUrl)
        return try StudyBundle(bundleUrl: bundleUrl)
    }

    /// Archives the bundle into a zstd-compressed tar file at `archiveUrl`.
    ///
    /// The archive is deterministic: identical bundle contents produce identical archives,
    /// on every platform.
    public func archive(to archiveUrl: URL, compressionLevel: Zstd.CompressionOptions.Level = .default) throws {
        let tar = try Tar.archive(Self.entries(ofDirectoryAt: bundleUrl))
        let compressed = try Zstd.compress(tar, options: .init(level: compressionLevel))
        try compressed.write(to: archiveUrl)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// The archive entries of the directory tree at `root`, sorted for a deterministic archive.
    private static func entries(ofDirectoryAt root: URL) throws -> [Tar.Entry] {
        let fileManager = FileManager.default
        // The enumerator canonicalizes symlinks in the URLs it yields (e.g. /var -> /private/var),
        // which the root's own path does not; resolving both the same way keeps the prefix aligned.
        let rootPath = root.resolvingSymlinksInPath().path(percentEncoded: false)
        var entries: [Tar.Entry] = []
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        for case let url as URL in enumerator ?? .init() {
            let entryPath = url.resolvingSymlinksInPath().path(percentEncoded: false)
            let relativePath = entryPath.trimmingPrefix(rootPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if fileManager.isDirectory(at: url) {
                entries.append(.directory(relativePath))
            } else {
                entries.append(.file(relativePath, contents: try Data(contentsOf: url)))
            }
        }
        return entries.sorted { $0.path < $1.path }
    }

    /// Writes the archive entries beneath `root`, rejecting any entry whose path escapes it.
    private static func write(_ entries: [Tar.Entry], to root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        // Resolve the root once and derive every target from it, so a symlink in the root's own
        // path cannot skew the containment check.
        let root = root.resolvingSymlinksInPath()
        let rootPath = canonicalPath(of: root)
        for entry in entries {
            let target = root.appending(path: entry.path).standardized
            let targetPath = canonicalPath(of: target)
            guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
                throw StudyBundleError.entryEscapesBundle(entry.path)
            }
            switch entry.kind {
            case .directory:
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            case .file:
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.contents.write(to: target)
            }
        }
    }

    /// A file URL's path with any trailing slash removed, so containment checks compare cleanly.
    private static func canonicalPath(of url: URL) -> String {
        "/" + url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
    }
}

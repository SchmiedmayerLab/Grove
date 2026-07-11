//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


extension FileManager {
    /// An error that can occur with some file system operations
    public enum FileManagerError: Error {
        case other(String)
    }
    
    /// Determines whether a file system item exists at the specified file url.
    @inlinable
    public func itemExists(at url: URL) -> Bool {
        fileExists(atPath: url.path)
    }
    
    /// Determines whether a file system item exists at the specified file url, and indicates whether the item is a directory.
    public func itemExists(at url: URL, isDirectory: inout Bool) -> Bool {
        var flag = ObjCBool(false)
        defer { isDirectory = flag.boolValue }
        return fileExists(atPath: url.path, isDirectory: &flag)
    }

    
    /// Determines whether a directory exists at the specified file url.
    public func isDirectory(at url: URL) -> Bool {
        var isDirectory = false
        return itemExists(at: url, isDirectory: &isDirectory) && isDirectory
    }
    
    
    /// Retrieves the contents of the directory at the specified url.
    public func contents(
        of dirUrl: URL,
        includingPropertiesForKeys: [URLResourceKey]? = nil, // swiftlint:disable:this discouraged_optional_collection
        options: DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        try contentsOfDirectory(at: dirUrl, includingPropertiesForKeys: includingPropertiesForKeys, options: options)
    }
    
    /// Ensures that a file url can be written to.
    public func prepareForWriting(
        to url: URL,
        intermediateDirectoriesAttributes: [FileAttributeKey: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
    ) throws {
        let dir = url.deletingLastPathComponent()
        if !isDirectory(at: dir) {
            try self.createDirectory(at: dir, withIntermediateDirectories: true, attributes: intermediateDirectoriesAttributes)
        }
    }

    
    /// Copies the item at `srcUrl` to `dstUrl`.
    @available(iOS 18, macOS 15, watchOS 11, *)
    public func copyItem(at srcUrl: URL, to dstUrl: URL, overwriteExisting: Bool) throws {
        if !itemExists(at: dstUrl) {
            try self.prepareForWriting(to: dstUrl)
            try self.copyItem(at: srcUrl, to: dstUrl)
        } else {
            guard overwriteExisting else {
                throw FileManagerError.other("Destination file already exists at location '\(dstUrl.path)'")
            }
            let tempUrl = URL.temporaryDirectory
                .appending(component: UUID().uuidString)
                .appendingPathExtension(srcUrl.pathExtension)
            try self.copyItem(at: srcUrl, to: tempUrl)
            _ = try self.replaceItemAt(dstUrl, withItemAt: tempUrl)
        }
    }
}

//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SpeziLocalization


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// An error that can occur when creating a Study Bundle.
    @_spi(APISupport)
    public enum CreateBundleError: Error {
        /// A `String` passed to e.g. ``StudyBundle/FileInput/init(fileRef:localization:contents:)-(_,_,String)`` didn't have a valid UTF-8 representation.
        case nonUTF8Input
        /// The Study Bundle failed to pass the validation checks.
        case failedValidation([BundleValidationIssue])
        /// A `URL` pointing to a directory was passed to a
        case isDirectory
    }
    
    
    /// A file resource which should be included when creating a ``StudyBundle``.
    public struct FileResourceInput {
        enum Source {
            case data(Data)
            case url(URL)
        }
        enum Target {
            case localized(LocalizedFileReference)
            case absolute(pathInBundle: String)
        }
        
        let source: Source
        let target: Target
        
        /// Creates a new `FileInput`, from raw `Data`.
        public init(fileRef: FileReference, localization: LocalizationKey, contents: Data) {
            source = .data(contents)
            target = .localized(.init(fileRef: fileRef, localization: localization))
        }
        
        /// Creates a new `FileInput`, from UTF8-encoded text.
        public init(fileRef: FileReference, localization: LocalizationKey, contents: String) throws {
            guard let contents = contents.data(using: .utf8) else {
                throw CreateBundleError.nonUTF8Input
            }
            self.init(fileRef: fileRef, localization: localization, contents: contents)
        }
        
        /// Creates a new `FileInput`, with the file contents at the specified URL.
        public init(fileRef: FileReference, localization: LocalizationKey, contentsOf url: URL) {
            source = .url(url)
            target = .localized(.init(fileRef: fileRef, localization: localization))
        }
        
        /// Creates a `FileResourceInput` that copies the contents of a file or directory into the study bundle.
        ///
        /// - parameter pathInBundle: The path, relative to the root of the study bundle, where the file or directory referenced by `url` should be placed.
        ///     If `url` is a file, `pathInBundle` must also contain the desired in-bundle filename.
        /// - parameter url: A URL to a file or directory that should be included in the bundle.
        public init(pathInBundle: String, contentsOf url: URL) {
            source = .url(url)
            target = .absolute(pathInBundle: pathInBundle)
        }
    }
    
    /// Creates a new Study Bundle, from the specified inputs.
    public static func writeToDisk(
        at bundleUrl: URL,
        definition: StudyDefinition,
        files: [FileResourceInput]
    ) throws -> StudyBundle {
        try Self.assertIsStudyBundleUrl(bundleUrl)
        let fileManager = FileManager.default
        if fileManager.itemExists(at: bundleUrl) {
            try fileManager.removeItem(at: bundleUrl)
        }
        try fileManager.createDirectory(at: bundleUrl, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(definition)
            let definitionUrl = bundleUrl.appendingPathComponent("definition.json")
            try data.write(to: definitionUrl)
        }
        for input in files {
            let url: URL
            switch input.target {
            case .localized(let fileRef):
                url = Self.fileUrl(for: fileRef, relativeTo: bundleUrl)
            case .absolute(let pathInBundle):
                url = bundleUrl.appending(path: pathInBundle)
            }
            switch input.source {
            case .data(let data):
                try fileManager.prepareForWriting(to: url)
                try data.write(to: url)
            case .url(let srcUrl):
                try fileManager.prepareForWriting(to: url)
                try fileManager.copyItem(at: srcUrl, to: url)
            }
        }
        let bundle = try Self(bundleUrl: bundleUrl)
        if case let issues = try bundle.validate(), !issues.isEmpty {
            try? fileManager.removeItem(at: bundle.bundleUrl)
            throw CreateBundleError.failedValidation(issues)
        }
        return bundle
    }
}

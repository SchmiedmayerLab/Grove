//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziLocalization


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// A reference to a non-localized version of a file within a StudyBundle.
    ///
    /// ``FileReference``s are non-localized references to files stored within a ``StudyBundle``; they can be resolved against a specific `Locale` using ``StudyBundle/resolve(_:in:using:fallback:)``.
    public struct FileReference: Hashable, Sendable, Codable, CustomStringConvertible {
        /// A ``StudyBundle/FileReference``'s category.
        ///
        /// ## Topics
        ///
        /// ### File Categories
        /// - ``consent``
        /// - ``questionnaire``
        /// - ``informationalArticle``
        ///
        /// ### Creating new File Categories
        /// - ``init(rawValue:)``
        public struct Category: RawRepresentable, Hashable, Codable, Sendable {
            /// The File Category for Consent documents.
            public static let consent = Self(rawValue: "consent")
            /// The File Category for questionnaires.
            public static let questionnaire = Self(rawValue: "questionnaire")
            /// The File Category for informative articles.
            public static let informationalArticle = Self(rawValue: "article")
            
            public let rawValue: String
            
            /// Creates a new file category
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
            
            public init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                rawValue = try container.decode(String.self)
            }
            
            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }
        
        /// The file category
        public let category: Category
        /// The filename, without localization or extension.
        public let filename: String
        /// The file extension.
        public let fileExtension: String
        
        public var description: String {
            if fileExtension.isEmpty {
                "\(category.rawValue)/\(filename)"
            } else {
                "\(category.rawValue)/\(filename).\(fileExtension)"
            }
        }
        
        /// Creates a new file reference.
        public init(category: Category, filename: String, fileExtension: String) {
            self.category = category
            self.filename = filename
            self.fileExtension = fileExtension
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// A localized file reference is the combination of a ``FileReference`` and a ``LocalizationKey``
    @_spi(APISupport)
    public struct LocalizedFileReference: Hashable, Sendable {
        let fileRef: FileReference
        let localization: LocalizationKey
        
        var filenameIncludingLocalization: String {
            "\(fileRef.filename)+\(localization.description)"
        }
        
        var fullFilenameIncludingLocalization: String {
            "\(fileRef.filename)+\(localization.description).\(fileRef.fileExtension)"
        }
    }
}


// MARK: URL/path resolution

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    static func folderUrl(for category: FileReference.Category, relativeTo baseUrl: URL) -> URL {
        baseUrl.appending(component: category.rawValue, directoryHint: .isDirectory)
    }
    
    static func fileUrl(for fileRef: FileReference, relativeTo baseUrl: URL) -> URL {
        folderUrl(for: fileRef.category, relativeTo: baseUrl)
            .appending(component: fileRef.filename, directoryHint: .notDirectory)
            .appendingPathExtension(fileRef.fileExtension)
    }
    
    static func fileUrl(for localizedFileRef: LocalizedFileReference, relativeTo baseUrl: URL) -> URL {
        folderUrl(for: localizedFileRef.fileRef.category, relativeTo: baseUrl)
            .appending(component: localizedFileRef.filenameIncludingLocalization, directoryHint: .notDirectory)
            .appendingPathExtension(localizedFileRef.fileRef.fileExtension)
    }
    
    
    static func parse(filename: String, in category: FileReference.Category) -> LocalizedFileReference? {
        guard filename.contains("+") else {
            logger.error("invalid file name '\(filename)'")
            return nil
        }
        var filename = filename[...]
        let baseName = String(filename.prefix { $0 != "+" })
        filename.removeFirst(baseName.count + 1)
        let rawLocalization = String(filename.prefix { $0 != "." })
        filename.removeFirst(rawLocalization.count + 1)
        let fileExtension = String(filename)
        guard let localization = LocalizationKey(rawLocalization) else {
            logger.error("failed to parse '\(rawLocalization)' into a localization")
            return nil
        }
        return .init(
            fileRef: FileReference(category: category, filename: baseName, fileExtension: fileExtension),
            localization: localization
        )
    }
    
    /// Resolves a `FileReference`, based on a locale.
    ///
    /// This function will fetch a list of all resources matching the ``FileReference``, and select the one with the best-matching locale.
    ///
    /// - Note: it is not guaranteed that the `URL` returned points to a file with a perfectly
    ///
    /// - returns: The `URL` of the resolved ``FileReference``, or `nil`
    public func resolve(
        _ fileRef: FileReference,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallback fallbackLocale: LocalizationKey? = .enUS
    ) -> URL? {
        resolve(
            fileRef: fileRef,
            locale: locale,
            localeMatchingBehaviour: localeMatchingBehaviour,
            fallback: fallbackLocale
        )?.url
    }
    
    func resolve(
        fileRef: FileReference,
        locale: Locale,
        localeMatchingBehaviour: LocaleMatchingBehaviour,
        fallback fallbackLocale: LocalizationKey?
    ) -> (url: URL, localizedFileRef: LocalizedFileReference)? {
        let dirUrl = Self.folderUrl(for: fileRef.category, relativeTo: bundleUrl)
        guard let candidateUrls = try? FileManager.default.contents(of: dirUrl) else {
            return nil
        }
        return LocalizedFileResolution.resolve(
            LocalizedFileResource("\(fileRef.filename).\(fileRef.fileExtension)", locale: locale),
            from: candidateUrls,
            using: localeMatchingBehaviour,
            fallback: fallbackLocale
        )
        .map { ($0.url, .init(fileRef: fileRef, localization: $0.localization)) }
    }
}

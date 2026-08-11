//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order

public import Foundation
public import struct ModelsR4.Questionnaire
#if canImport(OSLog)
import OSLog
#else
import Logging
#endif
import GroveFoundation
public import GroveLocalization
#if canImport(UniformTypeIdentifiers)
public import UniformTypeIdentifiers


// Gated because the extension reads `StudyBundle.fileExtension`, and `StudyBundle` is iOS 18+.
@available(iOS 18, macOS 15, watchOS 11, *)
extension UTType {
    /// A Study Bundle package.
    public static let studyBundle = UTType(filenameExtension: StudyBundle.fileExtension, conformingTo: .package)!
    // swiftlint:disable:previous force_unwrapping
}
#endif


/// A handle for working with a Study Definition bundle.
///
/// - Important: A ``StudyBundle`` represents an immutable resource; mutating the underlying file system item is not allowed and will result in undefined behaviour.
///     If you wish to make changes to a ``StudyBundle``, create a new bundle using the ``StudyBundle/writeToDisk(at:definition:files:)`` function,
///     or use ``copy(to:)`` to create a copy of the bundle's underlying file system item.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(bundleUrl:)``
/// - ``StudyBundleError``
///
/// ### Instance Properties
/// - ``bundleUrl``
/// - ``studyDefinition``
///
/// ### Accessing the Bundle's Contents
/// - ``consentText(for:in:using:fallbackLocale:)``
/// - ``questionnaire(for:in:using:fallback:)``
/// - ``displayTitle(for:in:using:)``
/// - ``resolve(_:in:using:fallback:)``
///
/// ### Operations
/// - ``copy(to:)``
///
/// ### Creating Study Bundles
/// - ``writeToDisk(at:definition:files:)``
/// - ``FileResourceInput``
///
/// ### Other
/// - ``fileExtension``
/// - ``FileReference``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct StudyBundle: Identifiable, Sendable {
    public enum StudyBundleError: Error {
        /// The URL passed to an operation does not point to a study bundle package.
        case notValidStudyBundleUrl
    }
    
    /// The file extension used by Study Bundles.
    public static let fileExtension = "studybundle"
    static let logger = Logger(subsystem: "org.grovealliance.study", category: "StudyBundle")
    
    /// The file url of the study definition bundle.
    public let bundleUrl: URL
    /// The bundle's ``StudyDefinition``
    public let studyDefinition: StudyDefinition
    
    public var id: UUID { studyDefinition.id }
    
    /// Read a study bundle from disk.
    public init(bundleUrl: URL) throws {
        try Self.assertIsStudyBundleUrl(bundleUrl)
        self.bundleUrl = bundleUrl
        do {
            let definitionUrl = bundleUrl.appendingPathComponent("definition.json")
            let data = try Data(contentsOf: definitionUrl)
            self.studyDefinition = try JSONDecoder().decode(
                StudyDefinition.self,
                from: data,
                configuration: .init(allowTrivialSchemaMigrations: true)
            )
        }
    }
    
    
    /// Writes a copy of the study bundle to the specified url.
    ///
    /// - parameter dstUrl: The url the study bundle should be written to. Note that this must be a valid url for a study bundle, i.e. it must use the ``StudyBundle/fileExtension``
    public func copy(to dstUrl: URL) throws {
        try Self.assertIsStudyBundleUrl(dstUrl)
        try FileManager.default.copyItem(at: bundleUrl, to: dstUrl, overwriteExisting: true)
    }
    
    
    /// Load a questionnaire resource from a ``FileReference``.
    public func questionnaire(
        for fileRef: FileReference,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallback fallbackLocale: LocalizationKey? = .enUS
    ) -> Questionnaire? {
        _decodeResource(for: fileRef, locale: locale, using: localeMatchingBehaviour, fallback: fallbackLocale) {
            try JSONDecoder().decode(Questionnaire.self, from: $0)
        }
    }
    
    /// Load a the quesrionnaire resource with the specified filename.
    public func questionnaire(
        named questionnaireName: String,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallback fallbackLocale: LocalizationKey? = .enUS
    ) -> Questionnaire? {
        questionnaire(
            for: .init(category: .questionnaire, filename: questionnaireName, fileExtension: "json"),
            in: locale,
            using: localeMatchingBehaviour,
            fallback: fallbackLocale
        )
    }
    
    /// Load a consent text resource from a ``FileReference``.
    public func consentText(
        for fileRef: FileReference,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallbackLocale: LocalizationKey?
    ) -> String? {
        _decodeResource(for: fileRef, locale: locale, using: localeMatchingBehaviour, fallback: fallbackLocale) {
            String(data: $0, encoding: .utf8)
        }
    }
    
    
    private func _decodeResource<T>(
        for fileRef: FileReference,
        locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour,
        fallback fallbackLocale: LocalizationKey?,
        decode: (Data) throws -> T?
    ) -> T? {
        guard let url = resolve(
            fileRef: fileRef,
            locale: locale,
            localeMatchingBehaviour: localeMatchingBehaviour,
            fallback: fallbackLocale
        )?.url else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(data)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// Throws an error if `url` isn't a valid study bundle url
    static func assertIsStudyBundleUrl(_ url: URL) throws(StudyBundleError) {
        guard url.hasDirectoryPath && url.pathExtension == Self.fileExtension else {
            throw .notValidStudyBundleUrl
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleUrl == rhs.bundleUrl
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleUrl)
    }
}

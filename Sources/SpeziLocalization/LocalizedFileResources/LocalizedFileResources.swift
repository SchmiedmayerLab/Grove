//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// A reference to a localized file.
///
/// Similar to how Foundation's `LocalizedStringResource` is used as a key for looking up a concrete localization of a string in an app's `Localizable.xcstrings` catalogue,
/// the `LocalizedFileResource` type is used as a key to look up a localized version of a file, from a set of candidates (see ``LocalizedFileResolution/resolve(_:from:using:fallback:)``).
///
/// ## Topics
///
/// ### Initializers
/// - ``init(_:locale:)``
/// - ``init(stringLiteral:)``
///
/// ### Properties
/// - ``name``
/// - ``locale``
///
/// ### Instance Methods
/// - ``locale(_:)``
///
/// ### File Resource Resolution
/// - ``Resolved``
/// - ``LocalizedFileResolution/resolve(_:from:using:fallback:)``
public struct LocalizedFileResource: Hashable, Sendable {
    /// The unlocalized filename, including the extension.
    public let name: String
    /// The locale to use when resolving the file reference.
    ///
    /// Use this property to override the locale used by the file resolution mechanism.
    public var locale: Locale
    
    /// Creates a new Localized File Resource.
    ///
    /// - parameter name: The non-localized name of the file.
    /// - parameter locale: The locale that should be used when resolving the file reference. Defaults to the user's current locale.
    public init(_ name: String, locale: Locale = .autoupdatingCurrent) {
        self.name = name
        self.locale = locale
    }
}


extension LocalizedFileResource: ExpressibleByStringLiteral {
    /// Creates a new Localized File Resource from a String literal, using the autoupdating current locale.
    public init(stringLiteral value: String) {
        self.init(value)
    }
}


extension LocalizedFileResource {
    /// Creates a new ``LocalizedFileResource`` that will get resolved using the specified `Locale`.
    public func locale(_ locale: Locale) -> Self {
        Self(name, locale: locale)
    }
}


// MARK: LocalizedFileResource.Resolved

@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizedFileResource {
    /// A resolved ``LocalizedFileResource``.
    ///
    /// ## Topics
    ///
    /// ### Instance Properties
    /// - ``url``
    /// - ``resource``
    /// - ``localization``
    /// - ``unlocalizedFilename``
    /// - ``fullFilenameIncludingLocalization``
    public struct Resolved: Hashable, Sendable {
        /// The underlying ``LocalizedFileResource`` used when looking up this localized file.
        public let resource: LocalizedFileResource
        /// The (localized) URL of the file.
        public let url: URL
        /// The URL's file name (including the file extension), with the localization suffix removed.
        public let unlocalizedFilename: String
        /// The localization info extracted from the localized filename's localization suffix.
        public let localization: LocalizationKey
        
        public var fullFilenameIncludingLocalization: String {
            guard let baseNameEndIdx = unlocalizedFilename.firstIndex(of: ".") else {
                return unlocalizedFilename
            }
            return "\(unlocalizedFilename[..<baseNameEndIdx])+\(localization)\(unlocalizedFilename[baseNameEndIdx...])"
        }
        
        private init(resource: LocalizedFileResource, url: URL, unlocalizedFilename: String, localization: LocalizationKey) {
            self.resource = resource
            self.url = url
            self.unlocalizedFilename = unlocalizedFilename
            self.localization = localization
        }
        
        /// Creates a new `LocalizedFileResource.Resolved` by parsing a URL pointing to a localized file resource.
        init?(resource: LocalizedFileResource, url: URL) {
            guard let components = url.lastPathComponent.parseLocalizationComponents(),
                  let fileExtension = components.fileExtension,
                  let localization = LocalizationKey(components.rawLocalization) else {
                return nil
            }
            self.init(
                resource: resource,
                url: url,
                unlocalizedFilename: "\(components.baseName).\(fileExtension)",
                localization: localization
            )
        }
        
        /// Creates a special `LocalizedFileResource.Resolved` representing an unlocalized file.
        ///
        /// For these instances, the `localization` will be set to the system language and an unknown region.
        init(unlocalized resource: LocalizedFileResource, url: URL) {
            self.resource = resource
            self.url = url
            self.unlocalizedFilename = url.lastPathComponent
            self.localization = .init(language: Locale.current.language, region: .unknown)
        }
    }
}

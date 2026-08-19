//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin) // LocalizedStringResource doesn't exist on Linux

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizedStringResource.BundleDescription {
    /// Convenience method to create a `BundleDescription.atURL()` from a given Bundle instance.
    ///
    /// - parameter bundle: The Bundle instance to retrieve the Bundle URL from.
    public static func atURL(from bundle: Bundle) -> LocalizedStringResource.BundleDescription {
        .atURL(bundle.bundleURL)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension LocalizedStringResource {
    /// Creates a localized `String` from the given `LocalizedStringResource`.
    ///
    /// - parameter locale: Specifies an override locale.
    /// - returns: The localized string.
    public func localizedString(for locale: Locale? = nil) -> String {
        if let locale {
            var resource = self
            resource.locale = locale
            return String(localized: resource)
        }
        return String(localized: self)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StringProtocol {
    @_documentation(visibility: internal)
    @available(*, deprecated, message: "Prefer explicitly using LocalizedStringResource.")
    public func localized(_: Bundle? = nil) -> LocalizedStringResource { // swiftlint:disable:this missing_docs
        LocalizedStringResource(stringLiteral: String(self))
    }
}
#endif

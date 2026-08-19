//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if !canImport(Darwin) // Foundation ships `LocalizedStringResource` on Darwin only.

package import Foundation


/// A stand-in for Foundation's `LocalizedStringResource` on platforms that don't have it.
///
/// Linux has no localization catalogues to resolve against, so this carries the key and hands it straight back.
/// Server-side output is therefore unlocalized — which is the point: a Grove target that only reaches for a
/// localized string to describe an error or a state stays compilable, instead of every such type becoming
/// Apple-only.
///
/// `package` on purpose. It exists so Grove can build on Linux, not as a localization API for anyone else, and
/// keeping it internal to the package means the eventual Foundation implementation can replace it without
/// breaking a public contract.
package struct LocalizedStringResource: Sendable, Hashable {
    /// Where a resource would be looked up, were there anything to look up.
    package enum BundleDescription: Sendable, Hashable {
        case main
        case atURL(URL)

        /// Mirrors the Darwin convenience of the same name.
        package static func atURL(from bundle: Bundle) -> Self {
            .atURL(bundle.bundleURL)
        }
    }

    /// The key, which doubles as the resolved value here.
    package let key: String
    /// Accepted and ignored; there is nothing to resolve differently per locale.
    package var locale: Locale?


    package init(_ key: String, bundle: BundleDescription? = nil, comment: String? = nil) {
        self.key = key
        _ = bundle
        _ = comment
    }

    /// Returns the key unchanged, matching the Darwin helper's signature.
    package func localizedString(for locale: Locale? = nil) -> String {
        key
    }
}


extension String {
    /// Resolves a ``LocalizedStringResource`` — to its key, since Linux has no catalogue to consult.
    package init(localized resource: LocalizedStringResource) {
        self = resource.key
    }
}

#endif

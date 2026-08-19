//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension Locale {
    /// Creates a new Locale, with the specified language and region.
    public init(language: Language, region: Region) {
        var components = Components(
            languageCode: language.languageCode,
            languageRegion: language.region
        )
        components.region = region
        self.init(components: components)
    }
}

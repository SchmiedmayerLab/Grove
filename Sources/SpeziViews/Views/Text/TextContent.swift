//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
enum TextContent {
    case string(_ value: String)
    case localized(_ value: LocalizedStringResource)

    func localizedString(for locale: Locale) -> String {
        switch self {
        case let .string(string):
            return string
        case let .localized(resource):
            return resource.localizedString(for: locale)
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
@usableFromInline
struct BackgroundMode: RawRepresentable, Codable, Hashable, Sendable {
    @usableFromInline static let fetch = BackgroundMode(rawValue: "fetch")

    @usableFromInline let rawValue: String

    @usableFromInline
    init(rawValue: String) {
        self.rawValue = rawValue
    }
}
#endif

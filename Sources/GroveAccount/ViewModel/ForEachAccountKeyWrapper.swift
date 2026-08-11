//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Helper type that wraps ``AccountKey`` metatypes to be identifiable for usage within `ForEach` views.
@available(iOS 18, macOS 15, watchOS 11, *)
struct ForEachAccountKeyWrapper: Identifiable {
    var id: ObjectIdentifier {
        accountKey.id
    }

    var accountKey: any AccountKey.Type

    init(_ accountKey: any AccountKey.Type) {
        self.accountKey = accountKey
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Represents the content of a typical text-based chat between user and system(s).
///
/// A ``Chat`` is nothing more than an ordered array of ``ChatEntity``s which contain the content of the individual messages.
@available(iOS 18, macOS 15, watchOS 11, *)
public typealias Chat = [ChatEntity]

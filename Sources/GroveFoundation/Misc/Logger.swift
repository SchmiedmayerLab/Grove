//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


#if canImport(os)
@_documentation(visibility: internal) @_exported import OSLog
#else
@_documentation(visibility: internal) @_exported import Logging
extension Logger {
    /// Creates a logger instance using the `os.Logger` initialization style.
    ///
    /// - Parameters:
    ///   - subsystem: Mapped to `label`.
    ///   - category: Stored in metadata key "category".
    public init(subsystem: String, category: String) {
        self.init(label: subsystem)
        self[metadataKey: "category"] = "\(category)"
    }
}
#endif

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(os)
import os
#endif

public enum LegacyIdentifierReport {
    #if canImport(os)
    private static let logger = Logger(subsystem: "org.grovealliance.legacyIdentifiers", category: "Migration")
    #endif

    /// Records that a running migration found data under a legacy identifier.
    ///
    /// - Parameters:
    ///   - identifier: The pre-Grove identifier that was found.
    ///   - subsystem: The module that found it, for the log.
    ///   - remedy: What the developer should do, when there is something they can do.
    public static func encountered(_ identifier: String, in subsystem: String, remedy: String? = nil) {
        let suffix = remedy.map { " \($0)" } ?? ""
        let message = "\(subsystem): migrating data stored under the legacy identifier '\(identifier)'.\(suffix)"
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #else
        print(message)
        #endif
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveProviderFHIR


/// Optional exact converter output for independent guide validation, and exact source times of fixture dates.
enum ProviderFixtures {
    /// The UTC timestamp of a whole-second date.
    static func timestamp(_ date: Date) throws -> ProviderTimestamp {
        try ProviderTimestamp(date.formatted(.iso8601))
    }

    /// The interval between the UTC timestamps of two whole-second dates.
    static func interval(_ start: Date, _ end: Date) throws -> ProviderInterval {
        try ProviderInterval(start: timestamp(start), end: timestamp(end))
    }

    static func write(_ results: [ProviderConversionResult], provider: String) throws {
        guard let path = ProcessInfo.processInfo.environment["GROVE_PROVIDER_FIXTURE_DIRECTORY"] else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(provider, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for result in results {
            guard let record = result.record else {
                continue
            }
            let name = Data(result.sourceToken.utf8).map { String(format: "%02x", $0) }.joined()
            try record.json.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveProviderFHIR


/// Optional exact converter output for independent guide validation.
enum ProviderFixtures {
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

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation


/// A family of checked-in test resources, and where a run regenerates it.
///
/// A family regenerates OUTSIDE the checkout: its environment variable (under `xcodebuild`, prefixed with
/// `TEST_RUNNER_`) names a directory the run writes into, and the files are copied into `Resources/` afterwards.
/// Writing into the checkout while Xcode runs the tests makes it re-resolve the package graph mid-run, so a
/// directory inside the checkout is refused. Each family has its own variable, so regenerating one never
/// regenerates, or stops verifying, another.
struct CheckedInResources: Sendable {
    /// No file of the family is checked in under the name a test asked for.
    struct Missing: Error, CustomStringConvertible {
        /// The file the test looked for.
        let file: String
        /// The family it belongs to.
        let family: CheckedInResources

        var description: String {
            "No \(file) is checked in; regenerate with \(family.environmentVariable) and copy it into Resources/\(family.subdirectory)"
        }
    }

    /// The regeneration directory lies inside the checkout the tests were built from.
    struct OutputInsideCheckout: Error, CustomStringConvertible {
        /// The directory the environment named.
        let directory: URL

        var description: String {
            "\(directory.path) lies inside the checkout; regenerate into a directory outside it and copy the files in afterwards"
        }
    }

    /// The goldens: one sorted-member graph per case and `outlines.json`.
    static let goldens = CheckedInResources(subdirectory: "Goldens", environmentVariable: "GROVE_GOLDEN_OUTPUT_DIR")
    /// The content corpus and, on regeneration, its change report.
    static let contentCorpus = CheckedInResources(subdirectory: "ContentCorpus", environmentVariable: "GROVE_CONTENT_CORPUS_OUTPUT_DIR")

    /// The checkout this test target was compiled from: the nearest directory above this file with a `Package.swift`,
    /// or nil when the sources are not on this machine (a regeneration directory cannot lie inside them then).
    private static let checkout: URL? = {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }()

    /// The subdirectory of `Resources/` the family is checked in under.
    let subdirectory: String
    /// The environment variable naming the regeneration directory.
    let environmentVariable: String

    /// The regeneration directory the environment names, or nil when this run verifies.
    var outputDirectory: URL? {
        ProcessInfo.processInfo.environment[environmentVariable]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Whether this run regenerates the family instead of verifying it.
    var isGenerating: Bool {
        outputDirectory != nil
    }

    /// The path components of `url` with every symbolic link in its longest existing prefix resolved, so
    /// `/tmp/x` and `/private/tmp/x` compare alike whether or not `x` exists yet.
    private static func resolvedComponents(_ url: URL) -> [String] {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            missing.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return existing.resolvingSymlinksInPath().pathComponents + missing
    }

    /// Every checked-in file of the family with `fileExtension`, by name, whichever way the build system laid the
    /// resources out: `.process` flattens the subdirectory, and a lookup under a subdirectory that is not there
    /// answers an empty array, not nil.
    func names(withExtension fileExtension: String) -> Set<String> {
        let urls = [subdirectory, nil]
            .compactMap { Bundle.module.urls(forResourcesWithExtension: fileExtension, subdirectory: $0) }
            .first { !$0.isEmpty } ?? []
        return Set(urls.map { $0.deletingPathExtension().lastPathComponent })
    }

    /// The bytes of one checked-in file of the family.
    func data(named name: String, withExtension fileExtension: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            throw Missing(file: "\(name).\(fileExtension)", family: self)
        }
        return try Data(contentsOf: url)
    }

    /// Writes one regenerated file into the regeneration directory, which must lie outside the checkout.
    func write(_ data: Data, toFile file: String) throws {
        guard let directory = outputDirectory else {
            return
        }
        if let checkout = Self.checkout, Self.resolvedComponents(directory).starts(with: Self.resolvedComponents(checkout)) {
            throw OutputInsideCheckout(directory: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(file))
    }
}

#endif

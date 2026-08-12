//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
@testable import GroveFoundation
import Testing


@Suite
struct StorageNamespaceTests {
    @Test
    func customNamespaceResolvesUnderApplicationSupport() throws {
        let namespace = StorageNamespace.custom("org.grovealliance.GroveFoundation.unitTests.\(UUID().uuidString)")
        let container = try namespace.containerURL()

        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #expect(container.deletingLastPathComponent().standardizedFileURL == applicationSupport.standardizedFileURL)
    }

    /// Resolution is pure. Creating on resolve would force every store relocation down its
    /// non-atomic path, because a destination that already exists cannot be committed by a rename.
    @Test
    func resolvingCreatesNothing() throws {
        let namespace = StorageNamespace.custom("org.grovealliance.GroveFoundation.unitTests.\(UUID().uuidString)")

        let container = try namespace.containerURL()
        let directory = try namespace.directory(.scheduler)

        #expect(!FileManager.default.fileExists(atPath: container.path))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test
    func directoryIsResolvedUnderTheContainer() throws {
        let namespace = StorageNamespace.custom("org.grovealliance.GroveFoundation.unitTests.\(UUID().uuidString)")
        let container = try namespace.containerURL()

        let directory = try namespace.directory(.scheduler)

        #expect(directory.lastPathComponent == "Scheduler")
        #expect(directory.deletingLastPathComponent().standardizedFileURL == container.standardizedFileURL)
    }

    /// `Library/Application Support` does not exist inside a fresh iOS app container, so creation has
    /// to build every intermediate directory.
    @Test
    func createDirectoryBuildsTheWholeChain() throws {
        let namespace = StorageNamespace.custom("org.grovealliance.GroveFoundation.unitTests.\(UUID().uuidString)")
        let container = try namespace.containerURL()
        defer { try? FileManager.default.removeItem(at: container) }

        let directory = try namespace.createDirectory(.scheduler)

        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: container.path))
    }

    @Test
    func resolvingIsIdempotent() throws {
        let namespace = StorageNamespace.custom("org.grovealliance.GroveFoundation.unitTests.\(UUID().uuidString)")

        let first = try namespace.directory(.scheduler)
        let second = try namespace.directory(.scheduler)
        #expect(first == second)
    }

    /// A process without a bundle identifier — `swift test`, command-line tools — must fail rather than
    /// pick a fallback, which would route every such process into one shared directory.
    ///
    /// Which branch runs depends on the runner: `xcodebuild` hosts tests in a bundle that has an
    /// identifier, `swift test` does not.
    @Test
    func appNamespaceDependsOnABundleIdentifier() throws {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            #expect(try StorageNamespace.app.containerURL().lastPathComponent == bundleIdentifier)
        } else {
            #expect(throws: StorageNamespace.ResolutionError.self) {
                _ = try StorageNamespace.app.containerURL()
            }
        }
    }

    @Test
    func namespacesOfDifferentKindsAreDistinct() {
        let custom = StorageNamespace.custom("a")
        #expect(custom != StorageNamespace.custom("b"))
        #expect(custom != StorageNamespace.appGroup("a"))
        #expect(custom == StorageNamespace.custom("a"))
    }
}


extension StorageNamespace.Component {
    fileprivate static let scheduler = Self("Scheduler")
}

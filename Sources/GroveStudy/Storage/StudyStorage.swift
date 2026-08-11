//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import GroveLegacyIdentifiers
import GroveStudyDefinition
import OSLog


private let logger = Logger(subsystem: "org.grovealliance.study", category: "Storage")


/// Resolves where the study manager keeps its store and its downloaded bundles, bringing both forward
/// from the documents directory on first launch after the update.
///
/// Ordering matters more here than elsewhere: `StudyManager.configure()` **deletes** any child of the
/// bundles directory that no enrollment refers to. A relocation left half-done is therefore destroyed
/// on the next launch rather than retried, so both moves commit atomically or not at all.
@available(iOS 18, macOS 15, watchOS 11, *)
enum StudyStorage {
    /// `Documents`, as it was before the move to Application Support.
    static let legacyDocumentsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// The store, inside the study directory.
    static let storeFilename = "store.sqlite"
    /// Downloaded bundles, inside the study directory.
    static let bundlesDirectoryName = "Bundles"

    /// The store's location, after bringing forward any predecessor.
    static func prepareStore(in namespace: StorageNamespace = .app, legacyRoot: URL = legacyDocumentsRoot) -> URL? {
        guard let directory = resolve(namespace) else {
            return nil
        }
        do {
            let outcome = try StoreRelocation.relocate(
                storeNamed: LegacyStorage.studyStore,
                from: legacyRoot,
                to: directory,
                renamedTo: storeFilename
            )
            if outcome == .relocated {
                LegacyIdentifierReport.encountered(LegacyStorage.studyStore, in: "GroveStudy", .duringMigration)
            }
        } catch {
            logger.error("Unable to relocate the study store: \(error)")
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Unable to create \(directory.path, privacy: .public): \(error)")
            return nil
        }
        return directory.appendingPathComponent(storeFilename)
    }

    /// The bundles directory, after bringing forward any predecessor.
    ///
    /// Enrollment directories are named `<uuid>.<extension>`, so the extension rename has to happen
    /// here too — a bundle left under the old extension is invisible to the lookup that matches it to
    /// an enrollment, and the cleanup pass then deletes it.
    static func prepareBundlesDirectory(in namespace: StorageNamespace = .app, legacyRoot: URL = legacyDocumentsRoot) -> URL? {
        guard let directory = resolve(namespace)?.appendingPathComponent(bundlesDirectoryName, isDirectory: true) else {
            return nil
        }
        let legacy = legacyRoot.appendingPathComponent(LegacyStorage.studyBundlesDirectory)
        do {
            let outcome = try StoreRelocation.relocateDirectory(from: legacy, to: directory)
            if outcome == .relocated {
                LegacyIdentifierReport.encountered(
                    LegacyStorage.studyBundlesDirectory,
                    in: "GroveStudy",
                    .duringMigration
                )
                removeLegacyParentIfEmpty(of: legacy)
            }
        } catch {
            logger.error("Unable to relocate the study bundles directory: \(error)")
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Unable to create \(directory.path, privacy: .public): \(error)")
            return nil
        }
        renameLegacyBundleExtensions(in: directory)
        return directory
    }

    private static func resolve(_ namespace: StorageNamespace) -> URL? {
        do {
            return try namespace.directory(.study)
        } catch {
            logger.error("Unable to resolve the study storage directory: \(error)")
            return nil
        }
    }

    /// Renames `<uuid>.spezistudybundle` enrollment directories onto the current extension.
    private static func renameLegacyBundleExtensions(in directory: URL) {
        let fileManager = FileManager.default
        for child in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] {
            let url = directory.appendingPathComponent(child)
            guard url.pathExtension == LegacyStorage.studyBundleFileExtension else {
                continue
            }
            let renamed = url.deletingPathExtension().appendingPathExtension(StudyBundle.fileExtension)
            guard !fileManager.fileExists(atPath: renamed.path) else {
                continue
            }
            do {
                try fileManager.moveItem(at: url, to: renamed)
                LegacyIdentifierReport.encountered(
                    LegacyStorage.studyBundleFileExtension,
                    in: "GroveStudy",
                    .duringMigration
                )
            } catch {
                logger.error("Unable to rename the study bundle \(child, privacy: .public): \(error)")
            }
        }
    }

    /// Removes the now-empty `edu.stanford.SpeziStudy` wrapper the bundles directory used to sit in.
    ///
    /// Only when empty — `removeItem` on a directory is recursive, and this one is in the user's
    /// documents directory where an app may keep its own data.
    private static func removeLegacyParentIfEmpty(of legacyBundles: URL) {
        let parent = legacyBundles.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? ["not-empty"]
        guard contents.isEmpty else {
            return
        }
        try? FileManager.default.removeItem(at: parent)
    }
}


extension StorageNamespace.Component {
    /// Where the study manager keeps its store and its downloaded bundles.
    static let study = Self("Study")
}

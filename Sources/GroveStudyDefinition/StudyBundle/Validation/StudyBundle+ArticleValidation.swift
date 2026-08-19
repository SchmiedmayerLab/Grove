//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import GroveLocalization


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    func validateArticles() throws -> [BundleValidationIssue] { // swiftlint:disable:this function_body_length
        let articleFileRefs = studyDefinition.components.compactMap {
            switch $0 {
            case .informational(let component):
                component.fileRef
            default:
                nil
            }
        }
        let fileManager = FileManager.default
        var issues: [BundleValidationIssue] = []
        for articleFileRef in articleFileRefs {
            /// all files for this fileRef's category
            let urls = (try? fileManager.contentsOfDirectory(
                at: Self.folderUrl(for: articleFileRef.category, relativeTo: bundleUrl),
                includingPropertiesForKeys: nil
            )) ?? []
            let candidates = LocalizedFileResolution.selectCandidatesIgnoringLocalization(
                matching: LocalizedFileResource(articleFileRef),
                from: urls
            )
            guard !candidates.isEmpty else {
                issues.append(.general(.noFilesMatchingFileRef(articleFileRef)))
                continue
            }
            let documents = try candidates.map {
                (document: try MarkdownDocument(contentsOf: $0.url), fileRef: $0)
            }
            let baseDocument = documents.first { $0.fileRef.localization == .enUS }
                ?? documents.first { $0.fileRef.localization.language.isEquivalent(to: .init(identifier: "en")) }
                ?? documents.first! // swiftlint:disable:this force_unwrapping - SAFETY: we have checked above that this is non-empty
            for (document, fileRef) in documents {
                guard let docId = document.metadata["id"] else {
                    issues.append(.article(.documentMetadataMissingId(
                        fileRef: .init(fileRef: articleFileRef, localization: fileRef.localization)
                    )))
                    continue
                }
                guard let baseId = baseDocument.document.metadata["id"] else {
                    issues.append(.article(.documentMetadataMissingId(
                        fileRef: .init(fileRef: articleFileRef, localization: baseDocument.fileRef.localization)
                    )))
                    continue
                }
                guard docId == baseId else {
                    issues.append(.article(.documentMetadataIdMismatchToBase(
                        baseLocalization: .init(fileRef: articleFileRef, localization: baseDocument.fileRef.localization),
                        localizedFileRef: .init(fileRef: articleFileRef, localization: fileRef.localization),
                        baseId: baseId,
                        localizedFileRefId: docId
                    )))
                    continue
                }
            }
        }
        return issues
    }
}

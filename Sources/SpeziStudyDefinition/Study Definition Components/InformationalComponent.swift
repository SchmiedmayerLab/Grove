//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// Study Component which prompts the participant to read an informational article
    public struct InformationalComponent: Identifiable, StudyDefinitionElement {
        public var id: UUID
        public var fileRef: StudyBundle.FileReference
        
        public init(id: UUID, fileRef: StudyBundle.FileReference) {
            precondition(fileRef.category == .informationalArticle)
            self.id = id
            self.fileRef = fileRef
        }
    }
}

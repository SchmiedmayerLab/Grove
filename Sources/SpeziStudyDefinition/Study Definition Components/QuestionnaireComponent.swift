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
    /// Study Component which prompts the participant to answer a questionnaire
    public struct QuestionnaireComponent: Identifiable, StudyDefinitionElement {
        /// - parameter id: the id of this study component, **not** of the questionnaire
        public let id: UUID
        public let fileRef: StudyBundle.FileReference
        
        public init(id: UUID, fileRef: StudyBundle.FileReference) {
            precondition(fileRef.category == .questionnaire)
            self.id = id
            self.fileRef = fileRef
        }
    }
}

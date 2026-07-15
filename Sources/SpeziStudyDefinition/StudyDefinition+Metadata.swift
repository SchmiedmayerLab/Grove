//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SpeziLocalization

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// Study Metadata
    public struct Metadata: Identifiable, StudyDefinitionElement {
        /// The icon that should be used when displaying the study to a user.
        public enum Icon: StudyDefinitionElement {
            case systemSymbol(String)
            case custom(URL)
        }
        
        /// The study's unique identifier.
        public var id: UUID
        /// The study's user-visible title.
        ///
        /// E.g., "MyHeart Counts"
        public var title: LocalizationsDictionary<String>
        /// The study's user-visible short title
        ///
        /// E.g., "MHC"
        public var shortTitle: LocalizationsDictionary<String>
        /// Icon that will be used for this study.
        public var icon: Icon?
        /// Long-form explanation of and/or introduction to the study.
        /// Is presented to the user
        public var explanationText: LocalizationsDictionary<String>
        /// Text that is presented to the user when they eg browse a list of studies they can enroll in
        public var shortExplanationText: LocalizationsDictionary<String>
        
        /// Other studies this study depends on.
        ///
        /// A participant can only enroll in this study, if they are already enrolled in the other study referenced via this property.
        public var studyDependency: StudyDefinition.ID?
        
        /// The criteria which need to be satisfied by a person wishing to participate in the study
        public var participationCriterion: ParticipationCriterion
        
        /// The study's consent file.
        public var consentFileRef: StudyBundle.FileReference?
        
        /// Creates a new `Metadata` object.
        public init(
            id: UUID,
            title: LocalizationsDictionary<String>,
            shortTitle: LocalizationsDictionary<String> = .init([.enUS: ""]),
            icon: Icon? = nil,
            explanationText: LocalizationsDictionary<String>,
            shortExplanationText: LocalizationsDictionary<String>,
            studyDependency: StudyDefinition.ID? = nil,
            participationCriterion: ParticipationCriterion,
            consentFileRef: StudyBundle.FileReference? = nil
        ) {
            self.id = id
            self.title = title
            self.shortTitle = shortTitle
            self.icon = icon
            self.explanationText = explanationText
            self.shortExplanationText = shortExplanationText
            self.studyDependency = studyDependency
            self.participationCriterion = participationCriterion
            self.consentFileRef = consentFileRef
        }
    }
}

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order closure_body_length

import Foundation
import struct ModelsR4.Questionnaire
import SpeziFoundation
import SpeziHealthKit
import SpeziLocalization
import SpeziScheduler
import SpeziStudyDefinition


extension UUID {
    // swiftlint:disable force_unwrapping
    fileprivate static let studyId = UUID(uuidString: "885099E4-6318-43CC-BFF1-7D7FAD1968F6")!
    fileprivate static let article0ComponentId = UUID(uuidString: "609FFB20-8D8C-4E95-932D-5F8ACD849D14")!
    fileprivate static let article1ComponentId = UUID(uuidString: "BFAF8AA3-211B-40AF-AE6F-3472DCEECFA8")!
    fileprivate static let article2ComponentId = UUID(uuidString: "C3651C0F-BF75-49FB-AB73-E8779746C621")!
    /// the "you have successfully answered the questionnaire" component
    fileprivate static let article3ComponentId = UUID(uuidString: "8024E8D3-B22C-4DCF-9F83-7B1557274DF5")!
    fileprivate static let questionnaireComponentId = UUID(uuidString: "898513A2-356A-4D45-AD41-81AED3CB18E8")!
    fileprivate static let healthComponentId = UUID(uuidString: "2B054B83-6165-4C45-AFA0-391701FD101B")!
    fileprivate static let schedule0Id = UUID(uuidString: "9E943F28-6B03-43CE-B7C7-1A0971C3D375")!
    fileprivate static let schedule1Id = UUID(uuidString: "E43521BF-899F-480B-9EA7-00558789DD69")!
    fileprivate static let schedule2Id = UUID(uuidString: "02330D9F-CF3E-4D8E-9F5B-D6A77268FEB5")!
    fileprivate static let schedule3Id = UUID(uuidString: "19CCB43F-34C8-49E3-B1C7-2BDF7311F3D9")!
    /// schedule for the "you have successfully answered the questionnaire" component
    fileprivate static let schedule4Id = UUID(uuidString: "0ECE08A0-9DC5-402A-9BD4-527F0FB11418")!
    // swiftlint:enable force_unwrapping
}

extension Locale.Language {
    static let english = Locale.Language(identifier: "en")
    static let spanish = Locale.Language(identifier: "es")
}


enum MockStudyRevision: UInt {
    // swiftlint:disable identifier_name
    // base version of the study
    case v1 = 1
    // this version removes the questionnaire component, so that we can test the component removal logic
    case v2 = 2
    // this version adds a second article component, so that we can test the component addition logic
    case v3 = 3
    // swiftlint:enable identifier_name
}


func mockStudy(revision: MockStudyRevision) throws -> StudyBundle { // swiftlint:disable:this function_body_length
    let definition = StudyDefinition(
        studyRevision: revision.rawValue,
        metadata: StudyDefinition.Metadata(
            id: .studyId,
            title: .init([.enUS: "TestStudy"]),
            explanationText: .init([.enUS: "This is a fake study, intended for testing the SpeziStudy package."]),
            shortExplanationText: .init([.enUS: "SpeziStudy fake test study"]),
            participationCriterion: .ageAtLeast(18) && !.ageAtLeast(60) && (.isFromRegion(.unitedStates) || .isFromRegion(.unitedKingdom)) && .speaksLanguage(.english) // swiftlint:disable:this line_length
        ),
        components: Array {
            StudyDefinition.Component.informational(.init(
                id: .article1ComponentId,
                fileRef: .init(category: .informationalArticle, filename: "Article1", fileExtension: "md")
            ))
            StudyDefinition.Component.healthDataCollection(.init(
                id: .healthComponentId,
                sampleTypes: SampleTypesCollection(
                    quantity: [.stepCount, .heartRate, .activeEnergyBurned],
                    correlation: [.bloodPressure],
                    category: [.sleepAnalysis]
                ),
                optionalSampleTypes: [],
                historicalDataCollection: .disabled
            ))
            StudyDefinition.Component.informational(.init(
                id: .article0ComponentId,
                fileRef: .init(category: .informationalArticle, filename: "Welcome", fileExtension: "md")
            ))
            StudyDefinition.Component.informational(.init(
                id: .article3ComponentId,
                fileRef: .init(category: .informationalArticle, filename: "SSQAnswered", fileExtension: "md")
            ))
            switch revision {
            case .v1:
                StudyDefinition.Component.questionnaire(.init(
                    id: .questionnaireComponentId,
                    fileRef: .init(category: .questionnaire, filename: "SocialSupport", fileExtension: "json")
                ))
            case .v2:
                let _ = () // swiftlint:disable:this redundant_discardable_let
            case .v3:
                StudyDefinition.Component.informational(.init(
                    id: .article2ComponentId,
                    fileRef: .init(category: .informationalArticle, filename: "Article2", fileExtension: "md")
                ))
            }
        },
        componentSchedules: Array {
            StudyDefinition.ComponentSchedule(
                id: .schedule0Id,
                componentId: .article0ComponentId,
                scheduleDefinition: .once(.event(.enrollment, time: .midnight)),
                completionPolicy: .afterStart,
                notifications: .disabled
            )
            StudyDefinition.ComponentSchedule(
                id: .schedule1Id,
                componentId: .article1ComponentId,
                scheduleDefinition: .repeated(.weekly(weekday: .wednesday, hour: 09, minute: 00)),
                completionPolicy: .anytime,
                notifications: .enabled(thread: .none)
            )
            switch revision {
            case .v1:
                StudyDefinition.ComponentSchedule(
                    id: .schedule2Id,
                    componentId: .questionnaireComponentId,
                    scheduleDefinition: .repeated(.weekly(weekday: .monday, hour: 09, minute: 00)),
                    completionPolicy: .anytime,
                    notifications: .enabled(thread: .none)
                )
                StudyDefinition.ComponentSchedule(
                    id: .schedule4Id,
                    componentId: .article3ComponentId,
                    scheduleDefinition: .once(.event(.completedTask(componentId: .questionnaireComponentId))),
                    completionPolicy: .anytime,
                    notifications: .enabled(thread: .none)
                )
            case .v2:
                let _ = () // swiftlint:disable:this redundant_discardable_let
            case .v3:
                StudyDefinition.ComponentSchedule(
                    id: .schedule3Id,
                    componentId: .article2ComponentId,
                    scheduleDefinition: .repeated(.weekly(weekday: .friday, hour: 09, minute: 00)),
                    completionPolicy: .anytime,
                    notifications: .enabled(thread: .none)
                )
            }
        }
    )
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .speziStudyBundle)
    return try StudyBundle.writeToDisk(
        at: url,
        definition: definition,
        files: Array {
            try StudyBundle.FileResourceInput(
                fileRef: .init(category: .informationalArticle, filename: "Article1", fileExtension: "md"),
                localization: .init(language: .english, region: .unitedStates),
                contents: """
                    ---
                    title: Article1 Title
                    id: 3734D98A-9477-486B-8116-42C81E4365B2
                    ---
                    """
            )
            try StudyBundle.FileResourceInput(
                fileRef: .init(category: .informationalArticle, filename: "Welcome", fileExtension: "md"),
                localization: .init(language: .english, region: .unitedStates),
                contents: """
                    ---
                    title: Welcome to the Study!
                    id: BA2435AF-1D12-42E1-9E30-D7C14F2544FF
                    ---
                    
                    # Welcome
                    We welcome you to our study :)
                    """
            )
            try StudyBundle.FileResourceInput(
                fileRef: .init(category: .informationalArticle, filename: "SSQAnswered", fileExtension: "md"),
                localization: .init(language: .english, region: .unitedStates),
                contents: """
                    ---
                    title: SSQAnswered
                    id: B50A769C-2417-47CA-96E4-044124DB68FE
                    ---
                    SSQAnswered
                    """
            )
            switch revision {
            case .v1:
                StudyBundle.FileResourceInput(
                    fileRef: .init(category: .questionnaire, filename: "SocialSupport", fileExtension: "json"),
                    localization: .init(language: .english, region: .unitedStates),
                    contents: try { () -> Data in
                        guard let url = Bundle.main.url(forResource: "SocialSupportQuestionnaire", withExtension: "json") else {
                            fatalError("Unable to find SocialSupport questionnaire")
                        }
                        return try Data(contentsOf: url)
                    }()
                )
            case .v2:
                let _ = () // swiftlint:disable:this redundant_discardable_let
            case .v3:
                try StudyBundle.FileResourceInput(
                    fileRef: .init(category: .informationalArticle, filename: "Article2", fileExtension: "md"),
                    localization: .init(language: .english, region: .unitedStates),
                    contents: """
                        ---
                        title: Article2 Title
                        id: D9ED4D99-4A31-444B-8058-96D9908F9ECC
                        ---
                        
                        # Article 2
                        heyoooo
                        """
                )
            }
        }
    )
}

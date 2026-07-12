//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziFoundation
import SpeziHealthKit
import SpeziLocalization


/// A type that can appear in a ``StudyDefinition``.
public typealias StudyDefinitionElement = Hashable & Codable & Sendable


/// Defines a Study, as a composition of metadata, components, and a schedule.
///
/// ## Studies
/// The SpeziStudy package models a study definition as a combination of study metadata, a list of study components, and a list of schedules for these components.
/// A study is identified via its ``id``, which must be unique across all studies and is not allowed to change throughout a study's lifetime.
///
/// A study's ``Metadata-swift.struct`` bundles all non-content-related information about the study, such as e.g. its unique id, user-visible title and description, participation criteria, etc.
/// The actual "content" of the study is defined via the ``Component`` and ``ComponentSchedule`` types: a study is a set of components, each of which represents some "thing" that can happen
/// as part of a user's participation in the study.
/// Additionally, the study contains a list of component schedules, which define when each component should be activated.
///
/// Currently, there are 3 kinds of components:
/// 1. ``InformationalComponent``s, which display static informational text, e.g. an article;
/// 2. ``QuestionnaireComponent``s, which prompt the participant to answer a questionnaire;
/// 3. ``HealthDataCollectionComponent``s, which configure and enable background collection of HealthKit data, including optional collection of historical data.
///
/// The ``StudyDefinition`` type is explicitly designed to be used with Swift's `Codable` infrastructure: it conforms to both the `Encodable` protocol, as well as `DecodableWithConfiguration`.
/// This allows apps to easily locally persist study definitions across app launches, and to transfer them between devices, e.g., an a study app could host its study definition on a server and then
/// on each launch dynamically fetch the current version of the study from the server, thereby eliminating the need to tie the study's definition (and any changes made to it) to specific versions of the app.
///
/// Every ``Component`` within a study definition is `Identifiable` and must have a strong identity, which is not allowed to change throughout the lifetime of the study.
///
/// ## Study Evolution
/// There are two kinds of possible changes the ``StudyDefinition`` type (as well as apps/libraries using it) must be able to cope with:
/// 1. **Study Content Evolution:** changes made within a study; e.g., adding a new component, modifying an existing component, adjusting some component's schedule, etc.
/// 2. **Study Definition Evolution:** changes made not to individual studies, but to the ``StudyDefinition`` type itself; e.g., adding/renaming/removing a property, changing a type, etc.
///
/// SpeziStudy provides facilities for gracefully dealing with these kinds of changes; see <doc:StudyEvolution> for more information on this.
///
/// ## Topics
///
/// ### Initializers
/// - ``init(studyRevision:metadata:components:componentSchedules:)``
/// - ``init(from:configuration:)``
///
/// ### Instance Properties
/// - ``studyRevision``
/// - ``metadata-swift.property``
/// - ``components``
/// - ``componentSchedules``
/// - ``id``
///
/// ### Study Metadata
/// - ``Metadata-swift.struct``
///
/// ### Study Components
/// - ``Component``
/// - ``InformationalComponent``
/// - ``QuestionnaireComponent``
/// - ``HealthDataCollectionComponent``
///
/// ### Study Schedule
/// - ``ComponentSchedule``
/// - ``ComponentSchedule/ScheduleDefinition-swift.enum``
///
/// ### Supporting Types
/// - ``StudyDefinitionElement``
/// - ``ParticipationCriterion``
///
/// ### Working with a study definition
/// - ``healthDataCollectionComponents``
/// - ``allCollectedHealthData(includingOptionalSampleTypes:)``
/// - ``component(withId:)``
/// - ``removeComponent(at:)``
/// - ``validate()``
@available(iOS 18, macOS 15, watchOS 11, *)
public struct StudyDefinition: Identifiable, Hashable, Sendable, Encodable, DecodableWithConfiguration {
    /// The ``StudyDefinition`` type's current schema version.
    public static let schemaVersion = Version(0, 13, 0)
    
    /// The revision of the study.
    ///
    /// This value should be incremented every time a new version of the study gets released.
    public var studyRevision: UInt
    /// The study's metadata.
    public var metadata: Metadata
    /// The study's components.
    public var components: [Component]
    /// The study's component schedules, defining which of the components should be activated when.
    public var componentSchedules: [ComponentSchedule]
    
    /// The study's unique identifier.
    ///
    /// - Important: This value **MUST** remain unchanged for the entire existence of a study.
    public var id: UUID { metadata.id }
    
    /// Creates a new `StudyDefinition`.
    public init(studyRevision: UInt, metadata: Metadata, components: [Component], componentSchedules: [ComponentSchedule]) {
        self.studyRevision = studyRevision
        self.metadata = metadata
        self.components = components
        self.componentSchedules = componentSchedules
    }
}


// MARK: Accessing stuff in a study, etc

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// All ``HealthDataCollectionComponent``s
    public var healthDataCollectionComponents: [HealthDataCollectionComponent] {
        components.compactMap { component in
            switch component {
            case .healthDataCollection(let component):
                component
            case .informational, .questionnaire, .timedWalkingTest:
                nil
            #if canImport(Darwin)
            case .customActiveTask:
                nil
            #endif
            }
        }
    }
    
    /// The combined, effective HealthKit data collection of the entire study.
    ///
    /// - parameter includingOptionalSampleTypes Whether optional sample types should be included in the result.
    ///     (See ``StudyDefinition/HealthDataCollectionComponent/optionalSampleTypes``.)
    public func allCollectedHealthData(includingOptionalSampleTypes: Bool) -> SampleTypesCollection {
        healthDataCollectionComponents.reduce(into: SampleTypesCollection()) { acc, component in
            acc.insert(contentsOf: component.sampleTypes)
            if includingOptionalSampleTypes {
                acc.insert(contentsOf: component.optionalSampleTypes)
            }
        }
    }
    
    /// Returns the first component with the specified id
    public func component(withId id: Component.ID) -> Component? {
        components.first { $0.id == id }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyBundle {
    /// The component's localized display title
    public func displayTitle(
        for component: StudyDefinition.Component,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default
    ) -> String? {
        switch component {
        case .informational(let component):
            documentMetadata(for: component, in: locale, using: localeMatchingBehaviour)?.title
        case .questionnaire(let component):
            questionnaire(
                for: component.fileRef,
                in: locale,
                using: localeMatchingBehaviour
            )?.title?.value?.string
        case .timedWalkingTest(let component):
            #if canImport(Darwin)
            String(localized: component.test.displayTitle)
            #else
            nil
            #endif
        #if canImport(Darwin)
        case .customActiveTask(let component):
            String(localized: component.activeTask.title)
        #endif
        case .healthDataCollection:
            nil
        }
    }
    
    /// The component's localized subtitle, if applicable.
    ///
    /// This function's behaviour depends on `component`'s type:
    /// - for informational components, the markdown file's `lede` metadata entry is fetched, if it exists;
    /// - for questionnaire components, the questionnaire's [`purpose`](https://hl7.org/fhir/R4/questionnaire-definitions.html#Questionnaire.purpose) is returned;
    /// - for timed walking test and health data collection components, nothing is returned.
    public func displaySubtitle(
        for component: StudyDefinition.Component,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default
    ) -> String? {
        switch component {
        case .informational(let component):
            documentMetadata(for: component, in: locale, using: localeMatchingBehaviour)?["lede"]
        case .questionnaire(let component):
            questionnaire(for: component.fileRef, in: locale, using: localeMatchingBehaviour)?.purpose?.value?.string
        case .timedWalkingTest:
            nil
        case .healthDataCollection:
            nil
        #if canImport(Darwin)
        case .customActiveTask(let component):
            component.activeTask.subtitle.map { String(localized: $0) }
        #endif
        }
    }
    
    /// Fetches the ``StudyDefinition/InformationalComponent``'s markdown document metadata.
    public func documentMetadata(
        for component: StudyDefinition.InformationalComponent,
        in locale: Locale,
        using localeMatchingBehaviour: LocaleMatchingBehaviour = .default,
        fallback fallbackLocale: LocalizationKey? = .enUS
    ) -> MarkdownDocument.Metadata? {
        guard let url = self.resolve(component.fileRef, in: locale, using: localeMatchingBehaviour, fallback: fallbackLocale),
              let text = (try? Data(contentsOf: url)).flatMap({ String(data: $0, encoding: .utf8) }) else {
            return nil
        }
        return try? MarkdownDocument.Metadata(parsing: text)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Swift.Duration {
    /// The duration's total length, in milliseconds.
    public var totalMilliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) * 1e-15
    }
    
    /// The duration's total length, in seconds.
    public var totalSeconds: Double {
        totalMilliseconds / 1000
    }
}

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
    /// A Component within a ``StudyDefinition``
    ///
    /// Study Components model schedulable and usually completable tasks or events that happen as part of a study participation.
    ///
    /// ### Component Kinds
    /// There are two kinds of components:
    /// 1. User-interactive components.
    ///     These are components which are displayed to the study participant, and typically require some kind of response.
    ///     Typically, these are used to initiate some form of data collection (e.g., prompting the user to answer a questionnaire, or to perform a six minute walking test),
    ///     but they can also be purely informational (e.g., displaying an article about some study-related topic to the user).
    /// 2. Internal, non-user-interactive components.
    ///     These are components which don't require any immediate user interaction and instead run in the background, e.g. to collect data.
    ///     An example of such a component is the background Health data collection.
    ///
    /// ### Component activation and Scheduling
    /// All study components operate on a schedule, which determines when (and how often) the component is activated.
    ///
    /// User-interactive components must have at least one explicit schedule defined in ``StudyDefinition/componentSchedules``; otherwise, they will simply be ignored and never do anything.
    /// Internal components are implicitly activated upon enrollment into the study.
    public enum Component: Identifiable, StudyDefinitionElement {
        /// Component Kind
        public enum Kind: Hashable, Sendable { // swiftlint:disable:this type_contents_order
            /// A user-interactive component
            case userInteractive
            /// An internal component
            case `internal`
        }
        /// A component that prompts the participant to read an informative article.
        case informational(InformationalComponent)
        /// A component that prompts the participant to anwer a questionnaire.
        case questionnaire(QuestionnaireComponent)
        /// A component that initiates background Health data collection.
        case healthDataCollection(HealthDataCollectionComponent)
        /// A component that prompts the participant to perform a Timed Walking Test.
        case timedWalkingTest(TimedWalkingTestComponent)
        #if canImport(Darwin)
        /// A component that prompts the participant to perform a custom Active Task.
        case customActiveTask(CustomActiveTaskComponent)
        #endif
        
        /// The components `id`, uniquely identifying it within the ``StudyDefinition``.
        public var id: UUID {
            switch self {
            case .informational(let component):
                component.id
            case .healthDataCollection(let component):
                component.id
            case .questionnaire(let component):
                component.id
            case .timedWalkingTest(let component):
                component.id
            #if canImport(Darwin)
            case .customActiveTask(let component):
                component.id
            #endif
            }
        }
        
        /// The Component's kind
        public var kind: Kind {
            switch self {
            case .informational, .questionnaire, .timedWalkingTest:
                .userInteractive
            #if canImport(Darwin)
            case .customActiveTask:
                .userInteractive
            #endif
            case .healthDataCollection:
                .internal
            }
        }
    }
}


// MARK: Mutating

@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// Removes the component at the specified index from the study.
    ///
    /// This removes both the component itself, as well as any schedules referencing it.
    public mutating func removeComponent(at idx: Int) {
        let component = components.remove(at: idx)
        componentSchedules.removeAll { $0.componentId == component.id }
    }
}

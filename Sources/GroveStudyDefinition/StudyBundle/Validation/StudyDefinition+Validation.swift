//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    struct ValidationResult {
        var warnings = Set<ValidationWarning>()
        var issues = Set<ValidationIssue>()
    }
    
    enum ValidationWarning: Hashable, CustomStringConvertible, Sendable {
        /// The component does not have any schedules associated with it
        case componentNotScheduled(Component)
        
        var description: String {
            diagnostic.message
        }
        
        var diagnostic: DiagnosticMessage {
            switch self {
            case .componentNotScheduled(let component):
                DiagnosticMessage("Study Component: Missing Schedule") {
                    DiagnosticMessage.Item("componentId", value: component.id)
                }
            }
        }
    }
    
    enum ValidationIssue: Hashable, CustomStringConvertible, Sendable {
        /// The study definition contains multiple components with the same id
        case conflictingComponents(id: UUID, [Component])
        /// The study definition contains multiple schedules with the same id
        case conflictingSchedules(id: UUID, [ComponentSchedule])
        /// The schedule is referencing a component that does not exist.
        case scheduleReferencingUnknownComponent(ComponentSchedule)
        /// A component contained a file ref that couldn't be resolved in the study bundle
        case unableToFindFileRef(StudyBundle.FileReference, Component)
        
        var description: String {
            diagnostic.message
        }
        
        var diagnostic: DiagnosticMessage {
            switch self {
            case let .conflictingComponents(id, components):
                DiagnosticMessage("Study: Conflicting Components with same id") {
                    DiagnosticMessage.Item("id", value: id)
                    for (idx, component) in components.enumerated() {
                        DiagnosticMessage.Item("component[\(idx)]", value: component.id)
                    }
                }
            case let .conflictingSchedules(id, schedules):
                DiagnosticMessage("Study: Conflicting Schedules with same id") {
                    DiagnosticMessage.Item("id", value: id)
                    for (idx, schedule) in schedules.enumerated() {
                        DiagnosticMessage.Item("schedule[\(idx)]", value: schedule.id)
                    }
                }
            case let .scheduleReferencingUnknownComponent(schedule):
                DiagnosticMessage("Study component schedule references unknown schedule") {
                    DiagnosticMessage.Item("schedule", value: schedule)
                }
            case let .unableToFindFileRef(fileRef, component):
                DiagnosticMessage("Study component: unable to resolve file ref") {
                    DiagnosticMessage.Item("fileRef", value: fileRef)
                    DiagnosticMessage.Item("component", value: component.id)
                }
            }
        }
    }
    
    
    /// Performs a simple validation of the study definition's integrity, checking e.g. that there are no references to non-existing componts.
    public func validate(in studyBundle: StudyBundle) -> Bool {
        validate(in: studyBundle).issues.isEmpty
    }
    
    
    func validate(in studyBundle: StudyBundle) -> ValidationResult {
        var result = ValidationResult()
        do { // check components
            let componentsById = components.grouped(by: \.id)
            for (id, components) in componentsById where components.count > 1 {
                result.issues.insert(.conflictingComponents(id: id, components))
            }
        }
        do { // check schedules
            let schedulesById = componentSchedules.grouped(by: \.id)
            for (id, schedules) in schedulesById where schedules.count > 1 {
                result.issues.insert(.conflictingSchedules(id: id, schedules))
            }
        }
        for component in components {
            if componentSchedules.count(where: { $0.componentId == component.id }) == 0, component.kind != .internal {
                result.warnings.insert(.componentNotScheduled(component))
            }
            let fileRefToCheck: StudyBundle.FileReference?
            switch component {
            case .informational(let component):
                fileRefToCheck = component.fileRef
            case .questionnaire(let component):
                fileRefToCheck = component.fileRef
            case .healthDataCollection, .timedWalkingTest:
                fileRefToCheck = nil
            #if canImport(Darwin)
            case .customActiveTask:
                fileRefToCheck = nil
            #endif
            }
            if let fileRefToCheck, studyBundle.resolve(fileRefToCheck, in: Locale(identifier: "en_US")) == nil {
                result.issues.insert(.unableToFindFileRef(fileRefToCheck, component))
            }
        }
        for schedule in componentSchedules where self.component(withId: schedule.componentId) == nil {
            result.issues.insert(.scheduleReferencingUnknownComponent(schedule))
        }
        return result
    }
}

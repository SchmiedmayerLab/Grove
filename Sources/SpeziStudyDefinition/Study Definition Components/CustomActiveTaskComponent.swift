//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(Darwin)
public import Foundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// Study Component which prompts the user to perform a custom active task
    public struct CustomActiveTaskComponent: Identifiable, StudyDefinitionElement {
        /// The identifier of the component itself, within the study definition.
        public var id: UUID
        /// The Active Task associated with this component.
        public var activeTask: ActiveTask
        
        public init(id: UUID, activeTask: ActiveTask) {
            self.id = id
            self.activeTask = activeTask
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition.CustomActiveTaskComponent {
    public struct ActiveTask: StudyDefinitionElement {
        public let identifier: String
        public let title: LocalizedStringResource
        public let subtitle: LocalizedStringResource?
        
        public init(identifier: String, title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
            self.identifier = identifier
            self.title = title
            self.subtitle = subtitle
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
        }
    }
}
#endif

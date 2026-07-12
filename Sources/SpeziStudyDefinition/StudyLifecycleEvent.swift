//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// An event that can happen over the course of a study's lifecycle.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum StudyLifecycleEvent: Hashable, Codable, Sendable {
    /// The event representing the participant's enrollment into the study
    case enrollment
    
    /// The event representing the study getting activated on a participant's phone.
    ///
    /// This event is closely related to ``enrollment``, but can also happen independently of it:
    /// whereas the ``enrollment`` event is only triggered the first time the user enrolls into the study,
    /// the ``activation`` is triggered every time the study is being set up and activated on the participant's phone.
    /// For example, if a user enrolls for the first time on February 17, that initial enrollment would trigger both the ``enrollment``
    /// and the ``activation`` events; but if the user on May 9th then deletes and re-installs the app and logs in again, that second
    /// time would only trigger the ``activation`` event.
    case activation
    
    /// The event representing the participant's unenrollment from the study
    case unenrollment
    
    /// The event representing the official end of the study
    case studyEnd
    
    /// The event representing the completion of a scheduled occurrence of a component.
    case completedTask(componentId: StudyDefinition.Component.ID)
}

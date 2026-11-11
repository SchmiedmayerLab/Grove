//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// What a record states about the converting application, its host and the participant's studies.
public struct ConversionFacts: Hashable, Sendable {
    public let application: ApplicationDevice
    public let host: HostDevice
    /// The enrollments in graph order.
    public let studies: [StudyEnrollment]

    package init(application: ApplicationDevice, host: HostDevice, studies: [StudyEnrollment]) {
        self.application = application
        self.host = host
        self.studies = studies
    }
}

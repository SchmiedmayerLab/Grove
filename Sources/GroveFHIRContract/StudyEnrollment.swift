//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


public enum StudyEnrollmentError: Error, Equatable, Sendable {
    case blankProtocolVersion
}


/// One known study association: the study, its exact protocol revision and the enrollment.
public struct StudyEnrollment: Hashable, Sendable {
    public let study: BusinessIdentifier
    public let protocolURL: FHIRPrimitive<Canonical>
    public let protocolVersion: String
    public let enrollment: BusinessIdentifier

    public init(
        study: BusinessIdentifier,
        protocolURL: FHIRPrimitive<Canonical>,
        protocolVersion: String,
        enrollment: BusinessIdentifier
    ) throws(StudyEnrollmentError) {
        guard !protocolVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .blankProtocolVersion
        }
        self.study = study
        self.protocolURL = protocolURL
        self.protocolVersion = protocolVersion
        self.enrollment = enrollment
    }
}

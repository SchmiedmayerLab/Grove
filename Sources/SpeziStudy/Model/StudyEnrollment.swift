//
// This source file is part of the My Heart Counts iOS application based on the Stanford Spezi Template Application project
//
// SPDX-FileCopyrightText: 2025 Stanford University
//
// SPDX-License-Identifier: MIT
//


import Foundation
import SpeziStudyDefinition
import SwiftData


/// Tracks a user's enrollment into a study.
@available(iOS 18, macOS 15, macCatalyst 18, watchOS 11, visionOS 2, *)
@Model
public final class StudyEnrollment: Identifiable {
    public typealias ID = UUID
    
    #Index<StudyEnrollment>([\.id])
    
    /// The primary key.
    @Attribute(.unique)
    public private(set) var id = UUID()
    
    /// The date when the participant enrolled into the study.
    ///
    /// This date is used as the reference for any relative date operations (e.g.: scheduling tasks relative to the start of someome's participation in a study).
    public private(set) var enrollmentDate: Date
    
    /// The identifier of the study.
    public private(set) var studyId: UUID
    /// The revision of the study.
    ///
    /// This property stores the current revision of the study as last seen by this object.
    public private(set) var studyRevision: UInt
    
    var studyBundleUrl: URL {
        StudyManager.studyBundlesDirectory.appendingPathComponent(self.id.uuidString, conformingTo: .speziStudyBundle)
    }
    
    /// The study.
    ///
    /// - Note: In some circumstances (e.g., if the `StudyDefinition` schema changes, and this enrollment has yet to be updated),
    ///     this value may initially be `nil` for a bit, until ``StudyManager/informAboutStudies(_:)`` was called.
    @Transient public private(set) lazy var studyBundle: StudyBundle? = {
        try? .init(bundleUrl: studyBundleUrl)
    }()
    
    
    /// Creates a new `StudyEnrollment` object.
    init(enrollmentDate: Date, studyBundle: StudyBundle) throws {
        self.enrollmentDate = enrollmentDate
        self.studyId = studyBundle.studyDefinition.id
        self.studyRevision = studyBundle.studyDefinition.studyRevision
        try updateStudyBundle(studyBundle, performValidityChecks: false)
    }
    
    /// Updates the enrollment's `StudyDefinition` to a new revision, if necessary.
    ///
    /// - Note: Attempting to update to a different study, or attempting to downgrade to an older revision, will result in the function simply not doing anything.
    func updateStudyBundle(_ newBundle: StudyBundle) throws {
        try updateStudyBundle(newBundle, performValidityChecks: true)
    }
    
    
    private func updateStudyBundle(_ newBundle: StudyBundle, performValidityChecks: Bool) throws {
        guard !performValidityChecks || (newBundle.id == studyId && newBundle.studyDefinition.studyRevision > studyRevision) else {
            return
        }
        try newBundle.copy(to: studyBundleUrl)
        self.studyBundle = try .init(bundleUrl: self.studyBundleUrl)
        studyRevision = newBundle.studyDefinition.studyRevision
    }
}

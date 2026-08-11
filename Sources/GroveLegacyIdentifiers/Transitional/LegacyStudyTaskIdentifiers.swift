//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Task identifiers `SpeziStudy` wrote into the scheduler store.
///
/// Primary keys: every recorded outcome references its task by identifier, so these are rewritten by
/// a store migration rather than simply replaced.
public enum LegacyStudyTaskIdentifiers {
    /// Prefix of every task the study manager created for a study component's schedule.
    public static let componentTaskPrefix = "edu.stanford.spezi.SpeziStudy.studyComponentTask."

    /// Prefix shared by every built-in study task category.
    public static let categoryPrefix = "edu.stanford.spezi.SpeziStudy.task."
}

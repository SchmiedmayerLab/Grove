//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveScheduler
import GroveSchedulerUI
import GroveStudy
import GroveViews
import SwiftUI


struct HomeTab: View {
    @Environment(\.taskCategoryAppearances)
    private var taskCategoryAppearances
    
    @Environment(StudyManager.self)
    private var studyManager
    
    @StudyManagerQuery(StudyEnrollment.self)
    private var enrollments
    
    @EventQuery(in: Date.today..<Date.nextWeek)
    private var events
    
    @State private var viewState: ViewState = .idle
    @State private var toggle = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    actions
                }
                Section {
                    ForEach(enrollments) { enrollment in
                        makeStudyEnrollmentRow(for: enrollment)
                    }
                }
                Section {
                    if events.isEmpty {
                        ContentUnavailableView("No Events", systemImage: "calendar")
                    } else {
                        makeEventsList(events)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .viewStateAlert(state: $viewState)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle("", isOn: $toggle)
                        .toggleStyle(.switch)
                }
            }
        }
    }
    
    @ViewBuilder private var actions: some View {
        let mockStudyV1 = try! mockStudy(revision: .v1) // swiftlint:disable:this force_try
        let mockStudyV2 = try! mockStudy(revision: .v2) // swiftlint:disable:this force_try
        let mockStudyV3 = try! mockStudy(revision: .v3) // swiftlint:disable:this force_try
        AsyncButton("Enroll in \(mockStudyV1.studyDefinition.metadata.title[.enUS] ?? "") (v\(mockStudyV1.studyDefinition.studyRevision))", state: $viewState) {
            try await studyManager.enroll(in: mockStudyV1)
        }
        AsyncButton("Update enrollment to study revision 2", state: $viewState) {
            try await studyManager.informAboutStudies([mockStudyV2])
        }
        .disabled(!enrollments.contains { $0.studyId == mockStudyV1.id && $0.studyRevision < mockStudyV2.studyDefinition.studyRevision })
        AsyncButton("Update enrollment to study revision 3", state: $viewState) {
            try await studyManager.informAboutStudies([mockStudyV3])
        }
        .disabled(!enrollments.contains { $0.studyId == mockStudyV1.id && $0.studyRevision < mockStudyV3.studyDefinition.studyRevision })
        AsyncButton("Unenroll from Study", state: $viewState) {
            if let enrollment = enrollments.first {
                try await studyManager.unenroll(from: enrollment)
            }
        }.disabled(enrollments.isEmpty)
    }
    
    @ViewBuilder
    private func makeStudyEnrollmentRow(for enrollment: StudyEnrollment) -> some View {
        VStack {
            if let study = enrollment.studyBundle?.studyDefinition {
                HStack {
                    Text(study.metadata.title[.enUS] ?? "")
                        .font(.headline)
                }
            }
            HStack {
                Text("Study ID")
                Spacer()
                Text(enrollment.studyId.uuidString)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack {
                Text("Study Revision")
                Spacer()
                Text("\(enrollment.studyRevision)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack {
                Text("Enrollment Date")
                Spacer()
                Text(DateFormatter.localizedString(from: enrollment.enrollmentDate, dateStyle: .short, timeStyle: .none))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
    
    @ViewBuilder
    private func makeEventsList(_ events: [Event]) -> some View {
        ForEach(events) { (event: Event) in
            InstructionsTile(event) {
                EventActionButton(event: event) {
                    `try`(with: $viewState) {
                        try event.complete()
                    }
                } label: {
                    let text = if let categoryLabel = label(for: event.task.category) {
                        "Complete \(categoryLabel): \(String(localized: event.task.title))"
                    } else {
                        "Complete \(String(localized: event.task.title))"
                    }
                    Text(text)
                }
            }
        }
    }
    
    private func label(for category: Task.Category?) -> String? {
        if let category, let appearance = taskCategoryAppearances[category] {
            String(localized: appearance.label)
        } else {
            nil
        }
    }
}


func `try`(with viewState: Binding<ViewState>, action: () throws -> Void) {
    do {
        try action()
    } catch {
        viewState.wrappedValue = .error((error as? any LocalizedError) ?? AnyLocalizedError(error: error))
    }
}

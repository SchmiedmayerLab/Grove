//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveScheduler
import GroveSchedulerUI
import GroveViews
import SwiftUI

enum DateSelection: Hashable {
    case today
    case tomorrow
    case date
}


enum AdditionalTestsTestCase: String, CaseIterable, Hashable, Identifiable {
    case shadowedOutcomes = "Shadowed Outcomes"
    case observeNewOutcomes = "Observe New Outcomes"
    
    var id: Self { self }
    
    @ViewBuilder @MainActor var view: some View {
        switch self {
        case .shadowedOutcomes:
            ShadowedOutcomeTestingView()
        case .observeNewOutcomes:
            ObserveNewOutcomesTestingView()
        }
    }
}


struct ScheduleView: View {
    /// The documentation shows the schedule alone: the test app's own controls are left out of the bar, and the
    /// state they would set is taken from the launch instead.
    private static var isDocumentation: Bool {
        ProcessInfo.processInfo.arguments.contains("--documentation")
    }

    private static var launchAlignment: HorizontalAlignment {
        switch argument(after: "--alignment") {
        case "center": .center
        case "trailing": .trailing
        default: .leading
        }
    }

    private static var launchDate: DateSelection {
        argument(after: "--date") == "tomorrow" ? .tomorrow : .today
    }

    @Environment(SchedulerModel.self)
    private var model

    @State private var alignment: HorizontalAlignment = ScheduleView.launchAlignment
    @State private var hidden = ScheduleView.isDocumentation // hide for screenshots
    @State private var dateSelection: DateSelection = ScheduleView.launchDate
    @State private var date = Date()
    @State private var additionalTestsTestCase: AdditionalTestsTestCase?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            scheduleList
                .navigationTitle("Schedule")
                .viewStateAlert(state: $model.viewState)
                .toolbar {
                    if !hidden {
                        toolbar
                    }
                }
                .sheet(item: $additionalTestsTestCase) { testCase in
                    testCase.view
                }
                .onChange(of: dateSelection, initial: true) {
                    switch dateSelection {
                    case .today:
                        date = .today
                    case .tomorrow:
                        date = .tomorrow
                    case .date:
                        guard let date = Calendar.current.date(byAdding: .day, value: 3, to: .now) else {
                            preconditionFailure("Failed to calulcate date")
                        }
                        self.date = date
                    }
                }
        }
    }
    
    @ViewBuilder private var scheduleList: some View {
        EventScheduleList(date: date) { event in
            InstructionsTile(event, alignment: alignment) {
                completeEvent(event)
            } more: {
                EventDetailView(event)
            }
        }
        .taskCategoryAppearance(for: .labResults, label: "Enter Lab Results")
        .taskCategoryAppearance(for: .timedWalkingTest, label: "Active Task", image: .system("figure.walk"))
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu("Extra Tests") {
                ForEach(AdditionalTestsTestCase.allCases, id: \.self) { testCase in
                    Button(testCase.rawValue) {
                        additionalTestsTestCase = testCase
                    }
                }
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Picker("Alignment", selection: $alignment) {
                Text("Leading").tag(HorizontalAlignment.leading)
                Text("Center").tag(HorizontalAlignment.center)
                Text("Trailing").tag(HorizontalAlignment.trailing)
            }
            Picker("Date", selection: $dateSelection) {
                Text("Today").tag(DateSelection.today)
                Text("Tomorrow").tag(DateSelection.tomorrow)
                Text("Date").tag(DateSelection.date)
            }
            Button("Hide Content", action: hide)
        }
    }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func hide() {
        hidden = true
        Swift::Task {
            try? await Swift::Task.sleep(for: .seconds(5))
            hidden = false
        }
    }
    
    private func completeEvent(_ event: Event) {
        do {
            try event.complete()
        } catch Event.CompletionError.preventedByCompletionPolicy {
            // SAFETY: we should never end up in here.
            // The InstructionsTile internally uses an EventActionButton, which is evaluating the event's task completion policy,
            // and will auto-disable itself if the event isn't allowed to be completed
            preconditionFailure("Event completion failed unexpectedly")
        } catch {
            // once https://github.com/swiftlang/swift/issues/79570 is fixed, we'll be able to remove this branch
            preconditionFailure("truly unreachable")
        }
    }
}


extension HorizontalAlignment: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

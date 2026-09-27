//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveViews
import SwiftUI


/// A day's three tasks in a heart health study, one per tile.
private enum DayTask {
    case walk
    case bloodPressure
    case medication

    var title: String {
        switch self {
        case .walk: "Morning Walk"
        case .bloodPressure: "Blood Pressure"
        case .medication: "Evening Medication"
        }
    }

    var time: String {
        switch self {
        case .walk: "Before 10:00 AM"
        case .bloodPressure: "Before breakfast"
        case .medication: "8:00 PM"
        }
    }

    var instructions: String {
        switch self {
        case .walk: "Thirty minutes at an easy pace. Your watch records the rest."
        case .bloodPressure: "Sit for five minutes, then take the reading on your left arm."
        case .medication: "One tablet with a glass of water."
        }
    }

    var action: String {
        switch self {
        case .walk: "Start"
        case .bloodPressure: "Record"
        case .medication: "Log"
        }
    }

    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .bloodPressure: "heart.fill"
        case .medication: "pills.fill"
        }
    }

    var color: Color {
        switch self {
        case .walk: .green
        case .bloodPressure: .red
        case .medication: .blue
        }
    }
}


struct TileExample: View {
    /// The documentation shows every alignment at once, without the controls that switch between them.
    private static let isDocumentation = ProcessInfo.processInfo.arguments.contains("--documentation")

    @State private var alignment: HorizontalAlignment = .leading
    @State private var showAllAlignments = TileExample.isDocumentation
    @State private var photoTime = false

    var body: some View {
        List {
            if showAllAlignments {
                Section {
                    tile(alignment: .leading, task: .walk)
                }
                Section {
                    tile(alignment: .center, task: .bloodPressure)
                }
                Section {
                    tile(alignment: .trailing, task: .medication)
                }
            } else {
                tile(alignment: alignment, task: .walk)
            }

            if !photoTime && !Self.isDocumentation {
                Section {
                    Picker("Alignment", selection: $alignment) {
                        Text("Leading").tag(HorizontalAlignment.leading)
                        Text("Center").tag(HorizontalAlignment.center)
                        Text("Trailing").tag(HorizontalAlignment.trailing)
                    }
                    Toggle("All Alignments", isOn: $showAllAlignments)
                }
            }
        }
            .navigationTitle("Today")
            .navigationBarBackButtonHidden(photoTime)
            .onChange(of: alignment) {
                startPhotoTime()
            }
            .onChange(of: showAllAlignments) {
                startPhotoTime()
            }
    }

    private func tile(alignment: HorizontalAlignment, task: DayTask) -> some View {
        SimpleTile(alignment: alignment) {
            TileHeader(alignment: alignment) {
                Image(systemName: task.symbol)
                    .foregroundStyle(task.color)
                    .font(.custom("Task Icon", size: 30, relativeTo: .headline))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .accessibilityHidden(true)
            } title: {
                Text(task.title)
            } subheadline: {
                Text(task.time)
            }
        } body: {
            Text(task.instructions)
        } footer: {
            Button {
            } label: {
                Text(task.action)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func startPhotoTime() {
        photoTime = true
        Task {
            try? await Task.sleep(for: .seconds(10))
            photoTime = false
        }
    }
}


extension HorizontalAlignment: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.key)
    }
}


#if DEBUG
#Preview {
    TileExample()
}
#endif

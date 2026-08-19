//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftUI


/// The front page: the three authoring routes, the renderer's own options, and everything
/// answered so far.
struct ContentView: View {
    @Environment(ResponsesStore.self) private var responsesStore

    @State private var shownResponse: ResponsesStore.Entry?

    var body: some View {
        List {
            Section("Authoring") {
                ForEach(AuthoringRoute.allCases) { route in
                    NavigationLink(route.title, value: route)
                        .accessibilityIdentifier("Route:\(route.title)")
                }
            }

            Section("Renderer") {
                NavigationLink("Existing Responses") {
                    ExistingResponsesExample()
                }
                .accessibilityIdentifier("Renderer:Existing Responses")
                NavigationLink("Completion Flow") {
                    CompletionFlowExample()
                }
                .accessibilityIdentifier("Renderer:Completion Flow")
            }

            responsesSection
        }
        .navigationTitle("Grove Questionnaire")
        .navigationDestination(for: AuthoringRoute.self) { route in
            page(for: route)
        }
        .sheet(item: $shownResponse) { entry in
            ResponseDetailsSheet(entry: entry)
        }
    }

    private var responsesSection: some View {
        Section("Responses") {
            LabeledContent("Completed", value: responsesStore.entries.count, format: .number)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Completed, \(responsesStore.entries.count)")
                .accessibilityIdentifier("CompletedCount")
            ForEach(responsesStore.entries) { entry in
                Button(entry.source) {
                    shownResponse = entry
                }
                .accessibilityIdentifier("Response:\(entry.source)")
            }
        }
    }

    @ViewBuilder
    private func page(for route: AuthoringRoute) -> some View {
        switch route {
        case .swiftDSL:
            SwiftDSLRoute()
        case .modelValues:
            ModelValuesRoute()
        case .fhir:
            FHIRRoute()
        }
    }
}

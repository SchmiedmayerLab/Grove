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
    @State private var showsSettings = false

    var body: some View {
        List {
            Section("Authoring") {
                ForEach(AuthoringRoute.allCases) { route in
                    NavigationLink(route.title, value: CatalogPage.route(route))
                        .accessibilityIdentifier("Route:\(route.title)")
                }
            }

            Section("Renderer") {
                ForEach([CatalogPage.existingResponses, .completionFlow], id: \.self) { page in
                    NavigationLink(page.title, value: page)
                        .accessibilityIdentifier("Renderer:\(page.title)")
                }
            }

            responsesSection
        }
        .navigationTitle("Grove Questionnaire")
        .navigationDestination(for: CatalogPage.self) { page in
            view(for: page)
        }
        .sheet(item: $shownResponse) { entry in
            ResponseDetailsSheet(entry: entry)
        }
        .toolbar {
            Button("Settings", systemImage: "gearshape") {
                showsSettings = true
            }
            .accessibilityIdentifier("Settings")
        }
        .sheet(isPresented: $showsSettings) {
            SheetSettingsView()
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
    private func view(for page: CatalogPage) -> some View {
        switch page {
        case .route(.swiftDSL):
            SwiftDSLRoute()
        case .route(.modelValues):
            ModelValuesRoute()
        case .route(.fhir):
            FHIRRoute()
        case .existingResponses:
            ExistingResponsesExample()
        case .completionFlow:
            CompletionFlowExample()
        }
    }
}

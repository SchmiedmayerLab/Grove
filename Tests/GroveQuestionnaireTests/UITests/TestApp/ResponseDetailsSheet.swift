//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import GroveViews
import ModelsR4
import SwiftUI


/// What the renderer handed back, read as FHIR: the metadata, the answer tree, and the JSON.
struct ResponseDetailsSheet: View {
    let entry: ResponsesStore.Entry

    private var response: QuestionnaireResponse {
        entry.response
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metadata") {
                    LabeledContent("Source", value: entry.source)
                    LabeledContent("Id", value: response.id?.value?.string ?? "—")
                    LabeledContent("Authored", value: (try? response.authored?.value?.asNSDate())?.formatted() ?? "—")
                    LabeledContent("Questionnaire", value: response.questionnaire?.value?.url.absoluteString ?? "—")
                    NavigationLink("FHIR JSON") {
                        FHIRSourceView(title: entry.source, json: response.prettyPrintedJSON)
                    }
                    .accessibilityIdentifier("ResponseJSON")
                }
                ForEach(response.item ?? [], id: \.self) { item in
                    Section {
                        ResponseItemView(item: item)
                    }
                }
            }
            .navigationTitle("Questionnaire Response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    DismissButton()
                }
            }
        }
    }
}


private struct ResponseItemView: View {
    let item: QuestionnaireResponseItem
    var depth = 0

    var body: some View {
        LabeledContent("linkId", value: item.linkId.value?.string ?? "—")
            .padding(.leading, indent)
            .accessibilityIdentifier("ResponseItem:\(item.linkId.value?.string ?? "—")")
        ForEach(item.answer ?? [], id: \.self) { answer in
            responseValueView(for: answer)
                .padding(.leading, indent)
        }
        // Every answer sits below at least one group item, so the nesting is rendered inline
        // rather than behind a drill-down that would hide all of it.
        ForEach(item.item ?? [], id: \.self) { item in
            ResponseItemView(item: item, depth: depth + 1)
        }
    }

    private var indent: CGFloat {
        CGFloat(depth) * 12
    }

    @ViewBuilder
    private func responseValueView(for answer: QuestionnaireResponseItemAnswer) -> some View {
        NavigationLink {
            AnswerView(answer: answer)
        } label: {
            if let value = answer.value {
                LabeledContent("Answer (\(value.typeDesc))", value: value.valueDesc)
            } else {
                LabeledContent("Answer", value: "nil value")
            }
        }
        .disabled(answer.value == nil && (answer.item ?? []).isEmpty)
    }
}


private struct AnswerView: View {
    let answer: QuestionnaireResponseItemAnswer

    var body: some View {
        Form {
            Section("Value") {
                if let value = answer.value {
                    LabeledContent("Type", value: value.typeDesc)
                    valueInfo(for: value)
                } else {
                    LabeledContent("Type", value: "nil")
                    LabeledContent("Value", value: "nil")
                }
            }
            ForEach(answer.item ?? [], id: \.self) { item in
                Section("Nested Item") {
                    ResponseItemView(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private func valueInfo(for value: QuestionnaireResponseItemAnswer.ValueX) -> some View {
        switch value {
        case .attachment:
            LabeledContent("Value", value: "(attachment)")
        case .boolean(let value):
            LabeledContent("Value", value: value.value?.bool.description ?? "nil")
        case .coding(let coding):
            LabeledContent("System", value: coding.system?.value?.url.absoluteString ?? "nil")
            LabeledContent("Code", value: coding.code?.value?.string ?? "nil")
            LabeledContent("Display", value: coding.display?.value?.string ?? "nil")
        case .date(let value):
            LabeledContent("Value", value: value.value?.description ?? "nil")
        case .dateTime(let value):
            LabeledContent("Value", value: value.value?.description ?? "nil")
        case .decimal(let value):
            LabeledContent("Value", value: value.value?.decimal.description ?? "nil")
        case .integer(let value):
            LabeledContent("Value", value: value.value?.integer.description ?? "nil")
        case .quantity(let value):
            LabeledContent("Value", value: value.value?.value?.decimal.description ?? "nil")
            LabeledContent("Unit", value: value.unit?.value?.string ?? "nil")
            if let comparator = value.comparator?.value {
                LabeledContent("Comparator", value: comparator.rawValue)
            }
            if let system = value.system?.value?.url {
                LabeledContent("System", value: system.absoluteString)
            }
            if let code = value.code?.value?.string {
                LabeledContent("Code", value: code)
            }
        case .reference(let value):
            if let reference = value.reference?.value?.string {
                LabeledContent("reference", value: reference)
            }
            if let type = value.type?.value?.url {
                LabeledContent("type", value: type.absoluteString)
            }
            if let identifier = value.identifier {
                LabeledContent("identifier", value: String(describing: identifier))
            }
            if let display = value.display?.value?.string {
                LabeledContent("display", value: display)
            }
        case .string(let value):
            LabeledContent("Value", value: value.value?.string ?? "nil")
        case .time(let value):
            LabeledContent("Value", value: value.value?.description ?? "nil")
        case .uri(let value):
            LabeledContent("Value", value: value.value?.url.absoluteString ?? "nil")
        }
    }
}


extension QuestionnaireResponseItemAnswer.ValueX {
    fileprivate var typeDesc: String {
        switch self {
        case .attachment: "attachment"
        case .boolean: "boolean"
        case .coding: "coding"
        case .date: "date"
        case .dateTime: "dateTime"
        case .decimal: "decimal"
        case .integer: "integer"
        case .quantity: "quantity"
        case .reference: "reference"
        case .string: "string"
        case .time: "time"
        case .uri: "uri"
        }
    }

    fileprivate var valueDesc: String {
        switch self {
        case .attachment:
            return "attachment"
        case .boolean(let value):
            return value.value?.bool.description ?? "nil"
        case .coding(let coding):
            let system = coding.system?.value?.url.absoluteString ?? ""
            let code = coding.code?.value?.string ?? ""
            return "\(system)/\(code)"
        case .date(let date):
            return date.value?.description ?? "nil"
        case .dateTime(let dateTime):
            return dateTime.value?.description ?? "nil"
        case .decimal(let value):
            return value.value?.decimal.description ?? "nil"
        case .integer(let value):
            return value.value?.integer.description ?? "nil"
        case .quantity(let quantity):
            let value = quantity.value?.value?.decimal.description ?? "nil"
            let unit = quantity.unit?.value?.string ?? ""
            return "\(value) \(unit)"
        case .reference(let reference):
            return reference.reference?.value?.string ?? "nil"
        case .string(let value):
            return value.value?.string ?? "nil"
        case .time(let time):
            return time.value?.description ?? "nil"
        case .uri(let value):
            return value.value?.url.absoluteString ?? "nil"
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The three ways a `Questionnaire` gets into the app, and the only thing that differs between
/// the examples in this catalog: all of them end up in the same renderer.
enum AuthoringRoute: String, CaseIterable, Identifiable, Hashable {
    case swiftDSL
    case modelValues
    case fhir

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .swiftDSL: "Swift DSL"
        case .modelValues: "Model Values"
        case .fhir: "FHIR JSON"
        }
    }
}

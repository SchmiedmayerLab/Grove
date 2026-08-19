//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SwiftDiagnostics
import SwiftSyntax


struct InstrumentNote: NoteMessage {
    let message: String
    let noteID: MessageID

    init(_ message: String, id: String) {
        self.message = message
        self.noteID = MessageID(domain: "GroveQuestionnaire", id: id)
    }
}


struct InstrumentDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String, id: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "GroveQuestionnaire", id: id)
        self.severity = severity
    }
}

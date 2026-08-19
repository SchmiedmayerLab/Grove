//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import PDFKit
import Grove
import GroveConsent


@Observable
@MainActor
final class TestAppConsentStorage: Module, EnvironmentAccessible, Sendable {
    var exportResults: [ConsentDocumentIdentifier: ConsentDocument.ExportResult] = [:]
}

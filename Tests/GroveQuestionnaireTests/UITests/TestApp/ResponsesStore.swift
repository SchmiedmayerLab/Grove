//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import struct ModelsR4.QuestionnaireResponse
import Observation


@Observable
@MainActor
final class ResponsesStore {
    var responses: [QuestionnaireResponse] = []
}

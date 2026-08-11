//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


enum LocationError: LocalizedError {
    case timeout
    case componentNotFound

    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "The Grove Location component was not found"
        case .timeout:
            return "Operation timed out"
        }
    }
}

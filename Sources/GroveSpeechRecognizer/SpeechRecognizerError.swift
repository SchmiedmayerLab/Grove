//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Why a recording could not start.
@available(iOS 18, macOS 15, watchOS 11, *)
public enum SpeechRecognizerError: LocalizedError {
    /// Speech recognition or the microphone was refused, or has not been asked for yet.
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            String(localized: "Speech recognition is not authorized.", bundle: .module)
        }
    }
}

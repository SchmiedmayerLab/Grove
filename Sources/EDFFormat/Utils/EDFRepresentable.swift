//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


protocol EDFRepresentable {
    var edfString: String { get }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension String: EDFRepresentable {
    var edfString: String {
        let result = replacing(" ", with: "_")
        return result.isEmpty ? "X" : result
    }
}


extension Optional: EDFRepresentable where Wrapped: EDFRepresentable {
    var edfString: String {
        switch self {
        case .none:
            "X"
        case let .some(value):
            value.edfString
        }
    }
}

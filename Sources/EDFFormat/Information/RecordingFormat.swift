//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// The data record format of an EDF file.
public enum RecordingFormat {
    /// EDF file with continuous recording (e.g., `EDF+C` or `BDF+C` code).
    case continuousRecording
    /// EDF file with interrupted recording (e.g., `EDF+D` or `BDF+D` code).
    case interruptedRecording
    /// Custom value for the reserved field.
    case custom(_ string: String = "")
}


extension RecordingFormat: Hashable, Sendable {}


extension RecordingFormat {
    init(from rawValue: String) {
        switch rawValue.uppercased() {
        case "EDF+C", "BDF+C":
            self = .continuousRecording
        case "EDF+D", "BDF+D":
            self = .interruptedRecording
        default:
            self = .custom(rawValue)
        }
    }

    func dataFormat(for type: FileFormat) -> String {
        let prefix = type.rawValue.uppercased()

        switch self {
        case .continuousRecording:
            return "\(prefix)+C"
        case .interruptedRecording:
            return "\(prefix)+D"
        case let .custom(string):
            return string
        }
    }
}

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// Static information about an BDF(+)/EDF(+) file.
public struct FileInformation {
    enum Duration {
        case integer(_ number: Int)
        case decimal(_ number: Double)
    }

    /// The local subject identification for the recording.
    public let subject: SubjectIdentification
    /// The local recording identification.
    public let recording: RecordingIdentification
    let _recordDuration: Duration // swiftlint:disable:this identifier_name

    /// The duration in seconds of a single data record.
    public var recordDuration: Double {
        switch _recordDuration {
        case let .integer(value):
            Double(value)
        case let .decimal(value):
            value
        }
    }


    /// Create a new file information.
    /// - Parameters:
    ///   - subject: The local subject identification for the recording.
    ///   - recording: The local recording identification.
    ///   - recordDuration: The duration in seconds of a single data record.
    public init(subject: SubjectIdentification, recording: RecordingIdentification, recordDuration: Int) {
        self.subject = subject
        self.recording = recording
        self._recordDuration = .integer(recordDuration)
    }

    /// Create a new file information.
    /// - Parameters:
    ///   - subject: The local subject identification for the recording.
    ///   - recording: The local recording identification.
    ///   - recordDuration: The duration in seconds of a single data record.
    public init(subject: SubjectIdentification, recording: RecordingIdentification, recordDuration: Double) {
        self.subject = subject
        self.recording = recording
        self._recordDuration = .decimal(recordDuration)
    }
}


extension FileInformation.Duration: Hashable, Sendable {}

extension FileInformation: Hashable, Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FileInformation {
    func verifyAsciiInputs() throws {
        try subject.verifyAsciiInputs()
        try recording.verifyAsciiInputs()
        switch _recordDuration {
        case let .integer(value):
            try verifyAsciiInput(value, maxLength: 8, for: "recordDuration")
        case let .decimal(value):
            try verifyAsciiInput(value, maxLength: 8, for: "recordDuration")
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Errors that can occur when encoding a EDF/BDF file.
public enum EDFEncodingError: Error {
    /// A provided field was too long to represent in the EDF file.
    case inputTooLong(field: String, _ value: String, expectedLength: Int)
    /// Non-ascii character was found in the given string.
    case invalidCharacter(field: String, _ character: Character, value: String)
    /// The provided ``DataRecord`` has an unexpected count of ``Channel``s.
    case invalidChannelCount(expected: Int, received: Int)
    /// The provided ``Channel`` has an unexpected count of samples.
    case invalidSampleCount(channel: SignalLabel, expected: Int, received: Int)
    /// The header was not written yet. Call ``GenericFileWriter/writeHeader()`` beforehand.
    case headerNotWritten
}


extension EDFEncodingError: Equatable {}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ByteCoding
public import Foundation
public import NIO


/// The structured representation of the `Local Recording Identification` field specified by EDF+.
public struct RecordingInformation {
    /// The start data and time of the recording.
    public let startDate: Date
    /// The hospital administration code of the investigation (e.g., EEG number or PSG number).
    public let code: String?
    /// A code specifying the responsible investigator or technician.
    public let investigatorCode: String?
    /// A code specifying the used equipment.
    public let equipmentCode: String?


    /// Create a new recording information.
    /// - Parameters:
    ///   - startDate: The start date of the recording.
    ///   - code: The hospital administration code of the investigation.
    ///   - investigatorCode: A code specifying the responsible investigator or technician.
    ///   - equipmentCode: A code specifying the used equipment.
    public init(startDate: Date, code: String? = nil, investigatorCode: String? = nil, equipmentCode: String? = nil) {
        self.startDate = startDate
        self.code = code
        self.investigatorCode = investigatorCode
        self.equipmentCode = equipmentCode
    }
}


/// Identify a recording.
public enum RecordingIdentification {
    /// An unstructured representation of the recording information as a `String`. Maximum length is 80 bytes.
    case unstructured(_ recording: String, startDate: Date)
    /// A structured representation of the recording information according to the EDF+ specification.
    case structured(_ recording: RecordingInformation)


    var startDate: Date {
        switch self {
        case let .unstructured(_, startDate):
            startDate
        case let .structured(recording):
            recording.startDate
        }
    }
}


extension RecordingInformation: Hashable, Sendable {}
extension RecordingIdentification: Hashable, Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension RecordingIdentification {
    func verifyAsciiInputs() throws {
        switch self {
        case let .unstructured(recording, _):
            try verifyAsciiInput(recording, maxLength: 80, for: "recordingIdentification")
        case let .structured(recording):
            try verifyAsciiInput(recording.edfString, maxLength: 80, for: "recordingIdentification")
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension RecordingInformation: EDFRepresentable {
    private static var longYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .init(identifier: "en_US")
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter
    }

    var edfString: String {
        "Startdate "
            + Self.longYearFormatter.string(from: startDate)
            + " "
            + code.edfString
            + " "
            + investigatorCode.edfString
            + " "
            + equipmentCode.edfString
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension RecordingIdentification: ByteEncodable {
    public func encode(to byteBuffer: inout ByteBuffer) {
        switch self {
        case let .unstructured(recording, _):
            byteBuffer.writeEDFAsciiTrimming(recording, length: 80)
        case let .structured(recording):
            byteBuffer.writeEDFAsciiTrimming(recording.edfString, length: 80)
        }
    }
}

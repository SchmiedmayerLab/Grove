//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import ByteCoding
import Foundation
import NIO


/// The structured representation of the `Local Subject Identification` field specified by EDF+.
public struct PatientInformation {
    /// The sex of the patient as defined by the EDF+ spec.
    public enum Sex: String {
        /// Female sex.
        case female = "F"
        /// Male sex.
        case male = "M"
    }

    /// The code by which the patient is known in the hospital administration.
    public let code: String?
    /// The sex of the patient.
    public let sex: Sex?
    /// The birthdate of the patient.
    public let birthdate: Date?
    /// The name of the patient without spaces.
    public let name: String?


    /// Create a new patient information.
    /// - Parameters:
    ///   - code: The code by which the patient is known in the hospital administration.
    ///   - sex: The sex of the patient.
    ///   - birthdate: The birthdate of the patient.
    ///   - name: The name of the patient without spaces.
    public init(code: String? = nil, sex: Sex? = nil, birthdate: Date? = nil, name: String? = nil) {
        self.code = code
        self.sex = sex
        self.birthdate = birthdate
        self.name = name
    }
}


/// Identify a subject.
public enum SubjectIdentification {
    /// An unstructured representation of the subject as a `String`. Maximum length is 80 bytes.
    case unstructured(_ subject: String)
    /// A structured representation of the subject according to the EDF+ specification.
    case structured(_ subject: PatientInformation)
}


extension PatientInformation.Sex: Hashable, Sendable {}
extension PatientInformation: Hashable, Sendable {}
extension SubjectIdentification: Hashable, Sendable {}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SubjectIdentification {
    func verifyAsciiInputs() throws {
        switch self {
        case let .unstructured(subject):
            try verifyAsciiInput(subject, maxLength: 80, for: "subjectIdentification")
        case let .structured(subject):
            try verifyAsciiInput(subject.edfString, maxLength: 80, for: "subjectIdentification")
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PatientInformation: EDFRepresentable {
    private static var birthdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .init(identifier: "en_US")
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter
    }

    var edfString: String {
        code.edfString
            + " "
            + sex.edfString
            + " "
            + (birthdate.map { Self.birthdayFormatter.string(from: $0) } ?? "X")
            + " "
            + name.edfString
    }
}


extension PatientInformation.Sex: EDFRepresentable {
    var edfString: String {
        rawValue
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SubjectIdentification: ByteEncodable {
    public func encode(to byteBuffer: inout ByteBuffer) {
        switch self {
        case let .unstructured(subject):
            byteBuffer.writeEDFAsciiTrimming(subject, length: 80)
        case let .structured(subject):
            byteBuffer.writeEDFAsciiTrimming(subject.edfString, length: 80)
        }
    }
}

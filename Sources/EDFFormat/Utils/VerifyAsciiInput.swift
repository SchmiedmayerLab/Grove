//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


func verifyAsciiInput<Value: BinaryInteger>(_ value: Value, maxLength: Int, for field: String) throws {
    try verifyAsciiInput(value.description, maxLength: maxLength, for: field)
}


func verifyAsciiInput(_ value: Double, maxLength: Int, for field: String) throws {
    try verifyAsciiInput(value.edfRepresentation(idealLength: maxLength), maxLength: maxLength, for: field)
}


func verifyAsciiInput(_ value: String, maxLength: Int, for field: String) throws {
    if value.count > maxLength {
        throw EDFEncodingError.inputTooLong(field: field, value, expectedLength: maxLength)
    }

    for character in value where !character.isASCII {
        throw EDFEncodingError.invalidCharacter(field: field, character, value: value)
    }
}


extension String {
    var isASCII: Bool {
        allSatisfy { character in
            character.isASCII
        }
    }
}


extension Double {
    func edfRepresentation(idealLength: Int) -> String {
        let format = "%.\(idealLength - 2)f"
        var stringValue = String(format: format, self)

        if stringValue.count > idealLength {
            guard let dotIndex = stringValue.firstIndex(of: ".") else {
                return stringValue // give up
            }

            let digitsLength = stringValue.distance(from: stringValue.startIndex, to: dotIndex)
            if digitsLength > idealLength {
                return stringValue // we can't shorten, give up
            }

            // otherwise, we just cut the amounts of precision we have
            stringValue = String(stringValue.prefix(idealLength))
        }

        return stringValue
    }
}

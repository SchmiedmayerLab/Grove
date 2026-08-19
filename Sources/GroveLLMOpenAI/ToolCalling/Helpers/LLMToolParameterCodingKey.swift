//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// In case of a `DecodingError` of the called function parameters to the ``LLMTool/Parameter``s, indicates where in the `DecodingError` occurred.
@available(iOS 18, macOS 15, watchOS 11, *)
struct LLMToolParameterCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int?
    
    
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
    }
}

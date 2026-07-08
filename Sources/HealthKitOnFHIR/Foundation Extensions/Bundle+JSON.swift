//
// This source file is part of the HealthKitOnFHIR open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


@available(macOS 13, *)
extension Foundation.Bundle {
    func decode<T: Decodable>(_ type: T.Type = T.self, from file: String) -> T {
        // We use the parameter order here with the default parameter at the beginning to follow the Swift API guidelines to
        // form API calls similar to English sentences.
        
        guard let url = self.url(forResource: file, withExtension: nil),
              let data = try? Data(contentsOf: url) else {
            fatalError("Could not load \(file) in the module.")
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("Could not decode \(file) in the module: \(error)")
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFHIRContract


enum SensorKitOutputIdentity {
    static func businessIdentifier(
        source: SensorKitSourceRecordID,
        discriminator: String
    ) throws -> BusinessIdentifier {
        // The value states its own inputs: the source record and which output of it this is.
        // Nothing is hashed, so a reader can tell the two apart without reversing anything.
        guard !source.value.contains("|"), !discriminator.contains("|") else {
            throw SensorKitConversionError.invalidIdentity(
                "a SensorKit output identity component must not contain a vertical bar"
            )
        }
        return try BusinessIdentifier(
            system: SensorKitContract.outputIdentifierSystem,
            value: "v1:\(source.value)|\(discriminator)"
        )
    }
}

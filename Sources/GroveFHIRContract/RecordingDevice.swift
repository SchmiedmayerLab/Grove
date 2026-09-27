//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


public enum RecordingDeviceError: Error, Equatable, Sendable {
    case blankStableUnitToken
    case blankName
    case blankManufacturer
    case blankModelNumber
}


/// The physical recorder, identified by a source-local token that stays stable for the same unit.
///
/// The token is never emitted. Adapters feed it to the deployment-scoped `recording-device`
/// identity instead of disclosing a platform identifier.
public struct RecordingDevice: Hashable, Sendable {
    public let stableUnitToken: String
    public let name: String?
    public let manufacturer: String?
    public let modelNumber: String?

    public init(
        stableUnitToken: String,
        name: String? = nil,
        manufacturer: String? = nil,
        modelNumber: String? = nil
    ) throws(RecordingDeviceError) {
        guard !stableUnitToken.isBlank else {
            throw .blankStableUnitToken
        }
        guard name?.isBlank != true else {
            throw .blankName
        }
        guard manufacturer?.isBlank != true else {
            throw .blankManufacturer
        }
        guard modelNumber?.isBlank != true else {
            throw .blankModelNumber
        }
        self.stableUnitToken = stableUnitToken
        self.name = name
        self.manufacturer = manufacturer
        self.modelNumber = modelNumber
    }
}

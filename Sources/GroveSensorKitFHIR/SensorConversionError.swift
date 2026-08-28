//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import GroveFHIRContract
public import ModelsR4


/// A typed failure for one record; batch conversion never drops input silently.
public struct SensorRecordFailure: Error, Equatable, Sendable {
    public let nativeRecordID: String
    public let sourceTypeIdentifier: String
    public let reason: SensorConversionError
}


/// Why one source record could not be converted.
public enum SensorConversionError: Error, Equatable, Sendable {
    case invalidConverterApplication(String)
    case invalidExchangeIdentity(String)
    case repositoryIDWithoutRecordingDevice
    case payloadTooLarge(byteCount: Int)
    /// A required typed FHIR reference is empty or targets the wrong resource type.
    case invalidReference(field: String, expectedResourceType: ResourceType)
    /// A repeated reference would create ambiguous duplicate graph relationships.
    case duplicateReference(field: String)
    /// A dependency raised a failure this domain does not model, named by type.
    ///
    /// Only the type is carried: a failing FHIR date conversion describes itself with the exact
    /// instant it could not convert, and that instant identifies a participant.
    case unexpectedConversionFailure(String)
}


extension SensorConversionError {
    /// Narrows any conversion failure to this published domain, so the converter's typed
    /// throws stay exhaustive even when a dependency raises its own error.
    init(conversionFailure error: any Error) {
        switch error {
        case let error as SensorConversionError:
            self = error
        case let error as ExchangeIdentityError:
            self = .invalidExchangeIdentity(String(describing: error))
        default:
            self = .unexpectedConversionFailure(String(reflecting: type(of: error)))
        }
    }
}

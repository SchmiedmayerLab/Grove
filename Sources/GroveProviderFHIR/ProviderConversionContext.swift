//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import GroveFHIRContract


/// Persist these facts with an acquisition before conversion, so a retry reproduces the same record version.
/// Connection ownership, consent and upstream credentials remain the caller's responsibility.
public struct ProviderConversionContext: Sendable {
    /// A complete provider key space, never inferred from the appearance of a native identifier.
    public enum Scope: Sendable {
        case account(BusinessIdentifier)
        case global(BusinessIdentifier)

        var identifier: BusinessIdentifier {
            switch self {
            case .account(let value), .global(let value): value
            }
        }
    }

    public let producer: ExchangeProducer
    public let scope: Scope
    public let instant: Date
    public let sourceTimeZone: TimeZone
    public let recordingDevice: RecordingDevice?
    public let sourceApplication: SourceApplicationDevice?

    public init(
        producer: ExchangeProducer,
        scope: Scope,
        instant: Date,
        sourceTimeZone: TimeZone,
        recordingDevice: RecordingDevice? = nil,
        sourceApplication: SourceApplicationDevice? = nil
    ) {
        self.producer = producer
        self.scope = scope
        self.instant = instant
        self.sourceTimeZone = sourceTimeZone
        self.recordingDevice = recordingDevice
        self.sourceApplication = sourceApplication
    }

    /// The same opaque source identity used by conversion, for durable acquisition and retry bookkeeping.
    /// A recognized token identifies its native key space; it does not establish conversion support or consent.
    public func sourceIdentity(
        provider: ProviderCapabilities.Provider,
        sourceType: String,
        nativeRecordID: String
    ) throws -> SourceRecordIdentity {
        let code: OpaqueIdentityScope.ProviderCode
        switch provider {
        case .googleHealthAPI: code = .googleHealthAPI
        case .oura: code = .oura
        case .withings: code = .withings
        }
        return try sourceIdentity(providerCode: code, sourceType: sourceType, nativeRecordID: nativeRecordID)
    }

    func sourceIdentity(
        providerCode: OpaqueIdentityScope.ProviderCode,
        sourceType: String,
        nativeRecordID: String
    ) throws -> SourceRecordIdentity {
        guard !nativeRecordID.isEmpty else { throw ProviderConversionError.invalidNativeIdentifier }
        guard ProviderContract.sources.contains(where: { $0.provider == providerCode.rawValue && $0.token == sourceType }) else {
            throw ProviderConversionError.invalidSourceType
        }
        switch (providerCode, scope) {
        case (.oura, .global), (.withings, .account), (.googleHealthAPI, .account): break
        default: throw ProviderConversionError.invalidScope
        }
        return try producer.identityScope.providerRecord(
            providerCode: providerCode,
            sourceType: sourceType,
            providerScope: scope.identifier,
            nativeRecordID: nativeRecordID
        )
    }
}

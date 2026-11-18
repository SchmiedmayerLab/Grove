//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


/// File-backed native recordings shared by the three connected-provider converters.
enum ProviderRecordingConversion {
    /// Preserves exact JSON bytes and their attachment checksum; no uniform sampling period or scalar result is invented.
    static func convert(_ recording: ProviderNativeRecording, context: ProviderConversionContext) throws -> ProviderConversionResult {
        let provider: OpaqueIdentityScope.ProviderCode
        let token: String
        switch recording.source {
        case .googleHeartRate: (provider, token) = (.googleHealthAPI, "heart-rate")
        case .ouraHeartRate: (provider, token) = (.oura, "heartrate")
        case .withingsActivity: (provider, token) = (.withings, "activityIntraday")
        case .withingsSleep: (provider, token) = (.withings, "sleepIntraday")
        }
        let attachment = Attachment(
            contentType: RegisteredRecordingFormat.providerRecording.registeredContentType?.asFHIRStringPrimitive(),
            hash: FHIRPrimitive(Base64Binary(with: recording.file.attachmentSHA1)),
            size: FHIRPrimitive(FHIRUnsignedInteger(Int32(recording.file.byteCount))),
            title: recording.title.asFHIRStringPrimitive(),
            url: FHIRPrimitive(FHIRURI(stringLiteral: recording.attachmentPath))
        )
        let period = try recording.interval.map {
            try Period(
                end: FHIRPrimitive(ExchangeInstant.fhirDateTime($0.end, offsetIn: context.sourceTimeZone)),
                start: FHIRPrimitive(ExchangeInstant.fhirDateTime($0.start, offsetIn: context.sourceTimeZone))
            )
        }
        let document = DocumentReference(
            content: [
                DocumentReferenceContent(
                    attachment: attachment,
                    format: Coding(
                        code: RegisteredRecordingFormat.providerRecording.rawValue.asFHIRStringPrimitive(),
                        system: RegisteredRecordingFormat.codeSystem.asFHIRURIPrimitive()
                    )
                )
            ],
            context: period.map { DocumentReferenceContext(period: $0) },
            meta: Meta(profile: [Profile.groveSensorRecordingDocument, Profile.providersRecordingDocument]),
            status: FHIRPrimitive(.current),
            type: CodeableConcept(text: recording.title.asFHIRStringPrimitive())
        )
        return try ProviderObservation.assemble(
            provider: provider,
            token: token,
            nativeID: recording.id,
            outputs: [
                .init(
                    role: "native-recording",
                    resource: .document(document),
                    artifactFormatCode: RegisteredRecordingFormat.providerRecording.rawValue
                )
            ],
            context: context
        )
    }
}

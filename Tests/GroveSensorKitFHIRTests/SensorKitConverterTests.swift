//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// One suite exercises the complete adapter graph surface against the normative catalog.
// swiftlint:disable type_body_length

import Foundation
import GroveFHIRContract
@testable import GroveSensorKitFHIR
import ModelsR4
import Testing


@Suite
struct GroveSensorKitFHIRConverterTests {
    private static let start = Date(timeIntervalSince1970: 1_787_009_400)
    private static var sourceID: SensorKitSourceRecordID {
        get throws {
            SensorKitSourceRecordID(try #require(
                UUID(uuidString: "879d9ea2-21cb-4527-b59b-2831dc4c84ab")
            ))
        }
    }

    private static var context: SensorKitConversionContext {
        get throws { try makeContext() }
    }

    private static func makeContext(
        sourceIdentifierDisclosurePolicy: GovernedSourceIdentifierDisclosurePolicy = .omit,
        visitLocationIdentifierSystem: IdentifierSystem = SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem
    ) throws -> SensorKitConversionContext {
        SensorKitConversionContext(
                subject: SensorFHIRIdentityTestSupport.subject,
                subjectIdentity: try SensorFHIRIdentityTestSupport.subjectIdentity,
                converter: SensorApplication(
                    sourceDeviceToken: "org.grovealliance.sensor-conformance",
                    name: "Sensor Conformance",
                    version: "0.5.0"
                ),
                converterHost: SensorFHIRIdentityTestSupport.converterHost,
                eventIdentifier: try SensorFHIRIdentityTestSupport.event(),
                entryNodeIdentifierSystem: SensorFHIRIdentityTestSupport.entryNodeIdentifierSystem,
                identityScope: try SensorFHIRIdentityTestSupport.identityScope,
                repositoryScope: try SensorFHIRIdentityTestSupport.repositoryScope,
                visitLocationIdentifierSystem: visitLocationIdentifierSystem,
                sourceIdentifierDisclosurePolicy: sourceIdentifierDisclosurePolicy,
                recordingDevice: SensorRecordingDevice(
                    stableUnitToken: "watch-42",
                    name: "Example Watch"
                ),
                converterWasGateway: true,
                sourceTimeZone: try #require(TimeZone(identifier: "America/Los_Angeles")),
                recordedAt: start.addingTimeInterval(60)
        )
    }

    private static func native(
        admission: SensorRawPayloadAdmission = .verifiedSanitizedInput,
        format: RegisteredRecordingFormat = .nativeRecording
    ) throws -> SensorKitNativeRecording {
        try SensorKitNativeRecording(
            title: "Exact SensorKit native record",
            format: format,
            payload: .inline(Data(#"{"flags":[0,2,1,0]}"#.utf8)),
            admission: admission
        )
    }

    @Test(arguments: [
        "sampled-data",
        "native-recording",
        "on-wrist",
        "device-usage-summary",
        "ecg-waveform",
        "visit-summary",
        "messages-usage-summary",
        "phone-usage-summary",
        "keyboard-metrics-summary",
        "sleep-session",
        "accelerometer-recording-summary",
        "ppg-recording-summary"
    ])
    func outputIdentityIsDeploymentScopedAndDoesNotDiscloseItsSource(discriminator: String) throws {
        let sourceID = try Self.sourceID
        let identifier = try SensorFHIRIdentityTestSupport.identityScope.sourceOutput(
            adapterID: "sensorkit",
            sourceType: "SRSensor.rotationRate",
            repositoryScope: SensorFHIRIdentityTestSupport.repositoryScope,
            nativeRecordID: sourceID.value,
            outputRole: RetractionTargetRole.primaryOutput.rawValue,
            outputDiscriminator: discriminator
        )
        #expect(identifier.systemValue ==
            "https://grovealliance.org/fhir/testing/identifiers/pseudonym/source-output/test/1")
        #expect(identifier.role == .sourceOutput)
        #expect(identifier.value.hasPrefix("v0:test:1:"))
        #expect(!identifier.value.contains(sourceID.value))
        #expect(!identifier.value.contains(discriminator))
    }

    @Test
    func rotationRateBuildsExactStructuredGraph() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: -0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: -0.01, z: 0.04),
                .init(timestamp: Self.start.addingTimeInterval(0.02), x: 0.01, y: -0.01, z: 0.02)
            ]
        )
        let conversion = try SensorKitConverter().convert(.rotationRate(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.id == nil)
        #expect(observation.issued == nil)
        #expect(observation.meta?.profile == [
            Profile.groveSensorSampledDataObservation,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.observationProfile))
        ])
        let identifierRoles = try observation.identifier?.map { try BusinessIdentifier($0).role }
        #expect(identifierRoles == [
            .sourceRecord,
            .sourceOutput
        ])
        #expect(conversion.recordingDocument == nil)
        #expect(conversion.provenance.target.count == 1)
        #expect(entries.count == 5)
        #expect(entries.allSatisfy { $0.fullUrl?.value?.url.absoluteString.hasPrefix("urn:uuid:") == true })
        try ExchangeIdentity.validate(entries: entries)

        guard case .sampledData(let sampled) = observation.value,
              case .period(let effective) = observation.effective else {
            Issue.record("Rotation rate must emit SampledData over a Period")
            return
        }
        #expect(sampled.period.value?.decimal == 10)
        #expect(sampled.dimensions.value?.integer == 3)
        #expect(sampled.data?.value?.string == "0.01 -0.02 0.03 0.02 -0.01 0.04 0.01 -0.01 0.02")
        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00.02-07:00")
    }

    @Test("Governed native record ID is opt-in and appears only on a structured primary")
    func governedNativeIDOnStructuredPrimary() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: 0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: 0.03, z: 0.04)
            ]
        )
        let nativeSystem: IdentifierSystem =
            "https://study.example.org/fhir/identifier/sensorkit-source-record"
        let context = try Self.makeContext(sourceIdentifierDisclosurePolicy: .authorized(
            system: nativeSystem,
            type: GovernedSourceIdentifierType(
                system: "https://study.example.org/fhir/CodeSystem/source-identifier-type",
                code: "sensorkit-record-id"
            )
        ))
        let conversion = try SensorKitConverter().convert(.rotationRate(record), context: context)
        #expect(conversion.observations.count == 1)
        let observation = try #require(conversion.observations.first)
        let nativeValue = try Self.sourceID.value
        let native = try #require(observation.identifier?.first {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        })

        #expect(native.value?.value?.string == nativeValue)
        #expect(observation.id == nil)
        #expect(conversion.recordingDocument == nil)
        let bundleJSON = String(decoding: try JSONEncoder().encode(conversion.bundle), as: UTF8.self)
        #expect(conversion.bundle.entry?.contains {
            $0.fullUrl?.value?.url.absoluteString.contains(nativeValue) == true
        } != true)
        #expect(bundleJSON.components(separatedBy: nativeValue).count == 2)
    }

    @Test("Visit location is retained exactly under the governed source-store system")
    func visitLocationUsesGovernedNativeIdentity() throws {
        let locationID = try #require(UUID(uuidString: "6f2692c2-7a8e-45db-8f2f-3300157fc0b4"))
        let record = SensorKitVisitRecord(
            sourceRecordID: try Self.sourceID,
            locationCategory: .work,
            distanceFromHomeMeters: 1_250,
            arrivalWindow: DateInterval(start: Self.start, duration: 60),
            departureWindow: DateInterval(start: Self.start.addingTimeInterval(3_600), duration: 60),
            locationID: locationID
        )

        let conversion = try SensorKitConverter().convert(.visit(record), context: Self.context)
        #expect(conversion.observations.count == 1)
        let observation = try #require(conversion.observations.first)
        #expect(observation.focus?.count == 1)
        let focus = try #require(observation.focus?.first)
        let identifier = try #require(focus.identifier)

        #expect(focus.reference == nil)
        #expect(focus.type?.value?.url.absoluteString == ResourceType.location.rawValue)
        #expect(identifier.system?.value?.url.absoluteString ==
            SensorFHIRIdentityTestSupport.visitLocationIdentifierSystem.rawValue)
        #expect(identifier.value?.value?.string == locationID.uuidString.lowercased())
        #expect(identifier.type == nil)
        let encoded = try JSONEncoder().encode(conversion.bundle)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains(locationID.uuidString.lowercased()))
    }

    @Test
    func ecgBuildsLosslessHybridGraphWithOneAuditTargetPerOutput() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.006,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [
                .init(offsetSeconds: 0, millivolts: [0.011, 0.023]),
                .init(offsetSeconds: 0.004, millivolts: [-0.005, 0.014])
            ],
            nativeRecording: try Self.native()
        )
        let conversion = try SensorKitConverter().convert(.electrocardiogram(record), context: Self.context)
        let observation = try #require(conversion.observations.first)
        let document = try #require(conversion.recordingDocument)
        let entries = try #require(conversion.bundle.entry)

        #expect(observation.meta?.profile == [
            Profile.groveSensorEcgObservation,
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.ecgObservationProfile))
        ])
        #expect(document.meta?.profile == [
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.sensorRecordingDocumentProfile)),
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.recordingDocumentProfile))
        ])
        let method = try #require(observation.method?.coding?.first)
        #expect(method.system?.value?.url.absoluteString == SensorKitContract.valueCodeSystem)
        #expect(method.code?.value?.string == "guided")
        #expect(method.display?.value?.string == "Guided")
        let format = try #require(document.content.first?.format)
        #expect(format.system?.value?.url.absoluteString == SensorKitContract.recordingFormatCodeSystem)
        #expect(format.code?.value?.string == "native-recording")
        #expect(observation.derivedFrom?.first?.reference?.value?.string == entries[1].fullUrl?.value?.url.absoluteString)
        #expect(conversion.provenance.target.count == 2)
        #expect(conversion.provenance.meta?.profile == [
            FHIRPrimitive(Canonical(stringLiteral: SensorKitContract.conversionProvenanceProfile))
        ])
        #expect(entries.count == 6)
        #expect(conversion.outputIdentifiers == (try SensorFHIRIdentityTestSupport.sensorKitOutputs(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.electrocardiogram",
            structuredDiscriminator: "ecg-waveform",
            includesNativeRecording: true
        )))
        guard case .period(let effective) = observation.effective,
              case .sampledData(let waveform) = observation.component?.first?.value else {
            Issue.record("ECG must emit one SampledData lead over a Period")
            return
        }
        #expect(effective.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(effective.end?.value?.description == "2026-08-17T16:30:00.006-07:00")
        #expect(waveform.period.value?.decimal == 2)
        #expect(waveform.data?.value?.string == "0.011 0.023 -0.005 0.014")
    }

    @Test("Hybrid graph discloses the governed source ID only on its structured primary")
    func governedNativeIDOnHybridPrimaryOnly() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.002,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [.init(offsetSeconds: 0, millivolts: [0.1, 0.2])],
            nativeRecording: try Self.native()
        )
        let nativeSystem: IdentifierSystem =
            "https://study.example.org/fhir/identifier/sensorkit-source-record"
        let conversion = try SensorKitConverter().convert(
            .electrocardiogram(record),
            context: Self.makeContext(sourceIdentifierDisclosurePolicy: .authorized(system: nativeSystem))
        )

        #expect(conversion.observations.count == 1)
        let observation = try #require(conversion.observations.first)
        #expect(observation.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        } == true)
        #expect(conversion.recordingDocument?.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
        } != true)
        #expect(conversion.recordingDocument?.id == nil)
    }

    @Test
    func inverseECGLeadIsNeverMislabeledAsStandardLeadI() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.002,
            frequencyHertz: 500,
            lead: .rightArmMinusLeftArm,
            guidance: .unguided,
            batches: [.init(offsetSeconds: 0, millivolts: [0.1, 0.2])],
            nativeRecording: try Self.native()
        )
        let conversion = try SensorKitConverter().convert(.electrocardiogram(record), context: Self.context)
        let codings = try #require(conversion.observations.first?.component?.first?.code.coding)

        #expect(codings.contains { $0.system?.value?.url.absoluteString == SensorKitContract.ecgLeadCodeSystem })
        #expect(!codings.contains {
            $0.system?.value?.url.absoluteString == "urn:iso:std:iso:11073:10101"
                && $0.code?.value?.string == "131329"
        })
    }

    @Test
    func nonuniformECGFailsClosed() throws {
        let record = SensorKitECGRecord(
            sourceRecordID: try Self.sourceID,
            startDate: Self.start,
            durationSeconds: 0.006,
            frequencyHertz: 500,
            lead: .leftArmMinusRightArm,
            guidance: .guided,
            batches: [
                .init(offsetSeconds: 0, millivolts: [0.1, 0.2]),
                .init(offsetSeconds: 0.005, millivolts: [0.3, 0.4])
            ],
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(.nonUniformTiming(index: 2))) {
            try SensorKitConverter().convert(.electrocardiogram(record), context: Self.context)
        }
    }

    @Test(arguments: SensorRawPayloadAdmission.allCases)
    func rawAdmissionIsConsumedButNeverSerialized(_ admission: SensorRawPayloadAdmission) throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(admission: admission, format: .heartRateSamples)
        )
        let conversion = try SensorKitConverter().convert(.raw(record), context: Self.context)
        let json = try #require(String(data: JSONEncoder().encode(conversion.bundle), encoding: .utf8))

        for value in SensorRawPayloadAdmission.allCases {
            #expect(!json.contains(value.rawValue))
        }
        #expect(conversion.observations.isEmpty)
        #expect(conversion.recordingDocument?.content.first?.format?.code?.value?.string == "heart-rate-samples")
        #expect(conversion.recordingDocument?.content.first?.format?.version == nil)
        #expect(conversion.recordingDocument?.context?.period?.start != nil)
        #expect(conversion.recordingDocument?.context?.period?.end != nil)
        #expect(conversion.recordingDocument?.context?.related == nil)
        #expect(conversion.provenance.target.count == 1)
    }

    @Test("A one-instant raw acquisition retains exact point coverage")
    func rawPointCoverageIsAdmitted() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 0),
            nativeRecording: try Self.native(format: .heartRateSamples)
        )
        let conversion = try SensorKitConverter().convert(.raw(record), context: Self.context)
        let period = try #require(conversion.recordingDocument?.context?.period)

        #expect(period.start == period.end)
    }

    @Test("A raw-only source discloses its governed ID on the sole DocumentReference")
    func governedNativeIDOnRawOnlyPrimary() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(format: .heartRateSamples)
        )
        let nativeSystem: IdentifierSystem =
            "https://study.example.org/fhir/identifier/sensorkit-source-record"
        let conversion = try SensorKitConverter().convert(
            .raw(record),
            context: Self.makeContext(sourceIdentifierDisclosurePolicy: .authorized(system: nativeSystem))
        )
        let nativeValue = try Self.sourceID.value

        #expect(conversion.observations.isEmpty)
        #expect(conversion.recordingDocument?.identifier?.contains {
            $0.system?.value?.url.absoluteString == nativeSystem.rawValue
                && $0.value?.value?.string == nativeValue
        } == true)
        #expect(conversion.recordingDocument?.id == nil)
    }

    @Test("A governed native ID cannot masquerade under generic or provider opaque namespaces")
    func governedNativeIDRejectsReservedSystem() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: 0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: 0.03, z: 0.04)
            ]
        )
        let identityScope = try SensorFHIRIdentityTestSupport.identityScope
        for reserved in [
            identityScope.systems.sourceRecord,
            identityScope.systems.providerOutput,
            identityScope.systems.providerArtifact
        ] {
            let context = try Self.makeContext(
                sourceIdentifierDisclosurePolicy: .authorized(system: reserved)
            )
            #expect(throws: SensorKitConversionError.invalidIdentity(
                "governed SensorKit source identifier system must not reuse a Grove opaque-identity namespace"
            )) {
                try SensorKitConverter().convert(.rotationRate(record), context: context)
            }
        }
    }

    @Test("Visit locations cannot reuse provider output or artifact namespaces")
    func visitLocationRejectsProviderOpaqueSystems() throws {
        let record = SensorKitRotationRateRecord(
            sourceRecordID: try Self.sourceID,
            samples: [
                .init(timestamp: Self.start, x: 0.01, y: 0.02, z: 0.03),
                .init(timestamp: Self.start.addingTimeInterval(0.01), x: 0.02, y: 0.03, z: 0.04)
            ]
        )
        let identityScope = try SensorFHIRIdentityTestSupport.identityScope
        for reserved in [
            identityScope.systems.providerOutput,
            identityScope.systems.providerArtifact
        ] {
            let context = try Self.makeContext(visitLocationIdentifierSystem: reserved)
            #expect(throws: SensorKitConversionError.invalidIdentity(
                "visitLocationIdentifierSystem must not reuse a Grove opaque-identity namespace"
            )) {
                try SensorKitConverter().convert(.rotationRate(record), context: context)
            }
        }
    }

    @Test
    func unregisteredRecordingFormatFailsClosed() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.heartRate",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native(format: .nativeRecording)
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .recordingFormatNotAdmitted("native-recording")
        )) {
            try SensorKitConverter().convert(.raw(record), context: Self.context)
        }
    }

    @Test
    func structuredOnlyStreamCannotClaimRawSupport() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.sleepSessions",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .sourceTypeHasNoRawContract("SRSensor.sleepSessions")
        )) {
            try SensorKitConverter().convert(.raw(record), context: Self.context)
        }
    }

    @Test
    func unknownSourceTokenIsNotAdmitted() throws {
        let record = try SensorKitRawRecord(
            sourceRecordID: try Self.sourceID,
            sourceToken: "SRSensor.headphoneMotion",
            effectivePeriod: DateInterval(start: Self.start, duration: 1),
            nativeRecording: try Self.native()
        )
        #expect(throws: SensorKitConversionError.invalidRecord(
            .sourceTypeNotAdmitted("SRSensor.headphoneMotion")
        )) {
            try SensorKitConverter().convert(.raw(record), context: Self.context)
        }
    }
}

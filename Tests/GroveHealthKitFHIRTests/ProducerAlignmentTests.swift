//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


private let groveFHIRRoot: URL = {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let candidates = [
        repositoryRoot.appendingPathComponent(".fhir/grove-fhir", isDirectory: true),
        repositoryRoot.deletingLastPathComponent().appendingPathComponent("grove-fhir", isDirectory: true)
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("catalog").path) } ?? candidates[0]
}()

private struct MissingEvent: Error {
    let name: String
}

private let groveFHIRIsAvailable = FileManager.default.fileExists(
    atPath: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json").path
)


/// Every optional parameter defaults the same way on every platform, and every disclosure omits.
@Suite
struct ProducerDefaultsTests {
    @Test("The event context defaults to an assembler without studies or repository rows")
    func eventContextDefaults() {
        let base = ExchangeEventContext.test()
        let context = ExchangeEventContext(
            subject: base.subject,
            event: base.event,
            identityScope: base.identityScope,
            repositoryScope: base.repositoryScope,
            application: base.application,
            host: base.host,
            conversionInstant: base.conversionInstant
        )
        #expect(context.converterRole == .assembler)
        #expect(context.studies.isEmpty)
        #expect(context.repositoryIDs.isEmpty)
    }

    @Test("Device facts default to nothing beyond what identifies the device")
    func deviceDefaults() throws {
        let application = try ApplicationDevice(name: "Grove", bundleIdentifier: "org.grovealliance.app", version: "1.0")
        #expect(application.build == nil)

        let host = try HostDevice(operatingSystemVersion: "26.0")
        #expect(host.name == nil && host.manufacturer == nil && host.modelNumber == nil)
        let current = HostDevice.current()
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(current.operatingSystemVersion == "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        #expect(current.name == nil && current.manufacturer == nil)

        let recording = try RecordingDevice(stableUnitToken: "unit-1")
        #expect(recording.name == nil && recording.manufacturer == nil && recording.modelNumber == nil)
    }

    @Test("Every HealthKit disclosure omits and the recording device resolves by local identifier")
    func healthKitOptionDefaults() {
        for options in [HealthKitConversionOptions(), .default, HealthKitConversionContext(event: .test()).options] {
            #expect(options.writer == .application)
            #expect(options.recordingDevice is HealthKitLocalIdentifierResolver)
            #expect(options.udiDisclosure == .omit)
            #expect(options.routeDisclosure == .omit)
            #expect(options.nativeIdentifierDisclosure == .omit)
        }
    }

    @Test("Optional identifiers default to nil")
    func identifierDefaults() throws {
        guard case .authorized(_, let type) = GovernedSourceIdentifierDisclosurePolicy.authorized(system: "https://store.example.org") else {
            Issue.record("An authorized policy keeps its shape")
            return
        }
        #expect(type == nil)

        let scope = ExchangeEventContext.test().identityScope
        let record = try scope.sourceRecord(
            adapterID: "healthkit",
            sourceType: "HKQuantityTypeIdentifierHeartRate",
            repositoryScope: ExchangeEventContext.test().repositoryScope,
            nativeRecordID: "record-1"
        )
        let output = try record.output(role: "primary", discriminator: "0")
        let target = try RetractionTarget(identifier: output, resourceType: .observation, role: .primaryOutput)
        #expect(target.nativeRecordIdentifier == nil)
    }
}


/// A warning is one registered `mobile-omission.*` row, and only those rows carry the warning severity.
@Suite
struct ProducerWarningTests {
    private static let warnings: [HealthKitConversionWarning] = [
        .recordingDeviceOmitted(deviceName: "Example Watch"),
        .sourceOffsetUnavailable(field: "Observation.effectiveDateTime"),
        .unmodeledMetadataWithheld(keys: ["com.example.custom"])
    ]

    private static func heartRate(device: HKDevice, metadata: [String: Any]) -> HKQuantitySample {
        let start = ExchangeEventContext.testInstant
        return HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: start,
            end: start,
            device: device,
            metadata: metadata
        )
    }

    @Test("Each warning case is one registry row of severity warning")
    func warningsAreWarningRows() throws {
        let codes = Self.warnings.map(\.diagnostic.code)
        #expect(codes == [
            "mobile-omission.recording-device",
            "mobile-omission.source-offset",
            "mobile-omission.unmodeled-metadata"
        ])
        for warning in Self.warnings {
            let rule = try #require(ExchangeGraphRule(rawValue: warning.diagnostic.code))
            #expect(rule.severity == .warning)
            #expect(warning.diagnostic.reason == rule.reason)
            #expect(warning.diagnostic.severity == .warning)
        }
        #expect(Self.warnings[1].diagnostic.location == "Observation.effectiveDateTime")
        #expect(Set(ExchangeGraphRule.allCases.filter { $0.severity == .warning }.map(\.rawValue)) == Set(codes))
    }

    @Test("Every error the adapters raise maps to a rule of severity error")
    func errorsAreErrorRows() {
        let errors: [HealthKitConversionError] = [
            .unsupportedSourceType(.workout),
            .invalidValue(.heartRate, .shapeInvalid),
            .ecgEvidence(.mismatchedSymptomContext)
        ]
        for error in errors {
            #expect(error.diagnostic.severity == .error)
            #expect(ExchangeGraphRule(rawValue: error.diagnostic.code)?.severity == .error)
        }
    }

    @Test("A conversion reports exactly what the graph lost")
    func conversionReportsOmissions() throws {
        let converter = HealthKitConverter()
        let context = HealthKitConversionContext()
        let unidentified = HKDevice(
            name: "Example Watch",
            manufacturer: "Example",
            model: "W42",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
        let identified = HKDevice(
            name: "Example Watch",
            manufacturer: "Example",
            model: "W42",
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: "unit-42",
            udiDeviceIdentifier: "udi-42"
        )

        let lossy = try converter.convert(Self.heartRate(device: unidentified, metadata: [:]), context: context)
        #expect(Set(lossy.warnings) == [
            .recordingDeviceOmitted(deviceName: "Example Watch"),
            .sourceOffsetUnavailable(field: "Observation.effectiveDateTime")
        ])

        let withheld = try converter.convert(
            Self.heartRate(
                device: identified,
                metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles", "com.example.zeta": "z", "com.example.custom": "x"]
            ),
            context: context
        )
        #expect(withheld.warnings == [.unmodeledMetadataWithheld(keys: ["com.example.custom", "com.example.zeta"])])

        let complete = try converter.convert(
            Self.heartRate(device: identified, metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]),
            context: context
        )
        #expect(complete.warnings.isEmpty, "the omitted UDI is the deployment's disclosure choice, not a loss")
    }

    @Test("An interval names each effective field that lost its offset")
    func intervalReportsBothBounds() throws {
        let start = ExchangeEventContext.testInstant
        let steps = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 120),
            start: start,
            end: start.addingTimeInterval(60)
        )
        let conversion = try HealthKitConverter().convert(steps, context: HealthKitConversionContext())
        #expect(conversion.warnings == [
            .sourceOffsetUnavailable(field: "Observation.effectivePeriod.start"),
            .sourceOffsetUnavailable(field: "Observation.effectivePeriod.end")
        ])
        #expect(conversion.warnings.map(\.diagnostic.location) == ["Observation.effectivePeriod.start", "Observation.effectivePeriod.end"])
    }
}


/// Every effective value takes the source's time zone, else UTC, and never the host's.
@Suite
struct EffectiveTimeZoneTests {
    private static let start = ExchangeEventContext.testInstant
    private static let end = start.addingTimeInterval(600)

    @Test("A stated zone gives every bound its offset and the timezone extension")
    func statedZone() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let period = try HealthKitConverter.effectivePeriod(start: Self.start, end: Self.end, sourceTimeZone: zone)
        #expect(period.start?.value?.description == "2026-08-17T16:30:00-07:00")
        #expect(period.end?.value?.description == "2026-08-17T16:40:00-07:00")
        for bound in [period.start, period.end] {
            #expect(bound?.extension?.map(\.url) == [Canonicals.timezone])
            #expect(bound?.extension?.first?.value == .code("America/Los_Angeles".asFHIRStringPrimitive()))
        }
    }

    @Test("Clock instants are UTC whatever zone the sample states, and only the effective time follows it")
    func clockInstantsAreUTC() throws {
        func conversion(_ zone: String) throws -> HealthKitConversionSet {
            let sample = HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
                start: Self.start,
                end: Self.start,
                metadata: [HKMetadataKeyTimeZone: zone]
            )
            return try HealthKitConverter().convert(sample, context: HealthKitConversionContext())
        }
        let pacific = try conversion("America/Los_Angeles")
        let tokyo = try conversion("Asia/Tokyo")
        for graph in [pacific, tokyo] {
            #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:30:00Z")
            #expect(graph.provenance.recorded.value?.description == "2026-08-17T23:30:00Z")
            guard case .dateTime(let occurred)? = graph.provenance.occurred else {
                Issue.record("The Provenance lost its occurred time")
                return
            }
            #expect(occurred.value?.description == "2026-08-17T23:30:00Z")
        }
        #expect(pacific.bundle.timestamp == tokyo.bundle.timestamp)
        #expect(pacific.observation.effective != tokyo.observation.effective)
    }

    @Test("Without a stated zone every bound is in UTC and carries no timezone extension")
    func unstatedZone() throws {
        let period = try HealthKitConverter.effectivePeriod(start: Self.start, end: Self.end, sourceTimeZone: nil)
        #expect(period.start?.value?.description == "2026-08-17T23:30:00Z")
        #expect(period.end?.value?.description == "2026-08-17T23:40:00Z")
        #expect(period.start?.extension == nil && period.end?.extension == nil)
        #expect(try HealthKitConverter.effectiveDateTime(Self.start, sourceTimeZone: nil).value?.description == "2026-08-17T23:30:00Z")
    }
}


/// The shared producer surface names every concept the way the other platforms do.
@Suite
struct ProducerSurfaceTests {
    private static let heartRate = HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
        start: ExchangeEventContext.testInstant,
        end: ExchangeEventContext.testInstant
    )

    @Test("The writer and its host are graph nodes a repository id can only name when the graph carries them")
    func writerNodes() throws {
        for node in [ExchangeGraphNode.writer, .writerHost] {
            let context = try HealthKitConversionContext(repositoryIDs: [node: RepositoryID("writer-1")])
            #expect(throws: HealthKitConversionError.repositoryIDWithoutNode(node)) {
                try HealthKitConverter().convert(Self.heartRate, context: context)
            }
        }
        let conversion = try HealthKitConverter().convert(Self.heartRate, context: HealthKitConversionContext(writer: .device))
        #expect(conversion.graphIdentifiers.writerSnapshot == nil)
        #expect(conversion.graphIdentifiers.writerHostSnapshot == nil)
    }

    @Test("A writer snapshot the converter already states is that entry, and its host goes with it")
    func writerSharingAConverterSnapshot() throws {
        func device(_ token: String, role: DeviceSnapshotRole) throws -> IdentifiedDevice {
            let context = ExchangeEventContext.test()
            let identity = try context.identityScope.deviceSnapshot(event: context.event, role: role, sourceDeviceToken: token)
            return IdentifiedDevice(resource: Device(), identity: identity)
        }
        let converterHost = try device("iPhone17,1|26.0.0", role: .host)
        let converterApplication = try device("org.grovealliance.test|1.0|1", role: .application)
        let stated: Set = [converterHost.identity, converterApplication.identity]

        let sameHost = HealthKitConverter.WriterDevices(
            application: try device("com.apple.Health|26.0", role: .application),
            host: try device("iPhone17,1|26.0.0", role: .host)
        )
        #expect(sameHost.entries(excluding: stated).map(\.identity) == [sameHost.application.identity])

        let converterItself = HealthKitConverter.WriterDevices(
            application: try device("org.grovealliance.test|1.0|1", role: .application),
            host: try device("iPhone16,2|25.4.0", role: .host)
        )
        #expect(converterItself.entries(excluding: stated).isEmpty)
    }

    @Test("A gateway application is its own snapshot: never the writer and never given a repository id")
    func gatewayApplicationSnapshot() throws {
        let gateway = ApplicationDevice.test(name: "Cuff Companion", bundleIdentifier: "com.example.cuff", version: "3.1")
        func context(_ repositoryIDs: [ExchangeGraphNode: RepositoryID]) -> HealthKitConversionContext {
            HealthKitConversionContext(event: .test(converterRole: .gatewayApplication(gateway), repositoryIDs: repositoryIDs))
        }
        let conversion = try HealthKitConverter().convert(Self.heartRate, context: context([.applicationDevice: RepositoryID("app-1")]))
        let snapshot = try context([:]).event.identityScope.deviceSnapshot(
            event: context([:]).event.event,
            role: .application,
            sourceDeviceToken: gateway.sourceDeviceToken
        )
        let device = try #require(conversion.graph.resource(Device.self, at: snapshot))
        #expect(device.id == nil)
        #expect(conversion.graphIdentifiers.writerSnapshot == nil)
        #expect(conversion.converterApplication.id?.value?.string == "app-1")
        #expect(throws: HealthKitConversionError.repositoryIDWithoutNode(.writer)) {
            try HealthKitConverter().convert(Self.heartRate, context: context([.writer: RepositoryID("writer-1")]))
        }
    }

    @Test("The application and host snapshots are minted from the tokens the devices state")
    func deviceTokensMintTheSnapshots() throws {
        let application = ApplicationDevice.test
        #expect(application.sourceDeviceToken == "org.grovealliance.test|1.0")
        #expect(ApplicationDevice.test(name: "Grove", bundleIdentifier: "org.grovealliance.test", version: "1.0", build: "7")
            .sourceDeviceToken == "org.grovealliance.test|1.0|7")
        #expect(HostDevice.test.sourceDeviceToken == "Phone One|20.1")
        #expect(try HostDevice(operatingSystemVersion: "26.0").sourceDeviceToken == "|26.0")
        let current = HostDevice.current()
        #expect(current.modelNumber?.isEmpty == false)
        #expect(current.sourceDeviceToken == "\(current.modelNumber ?? "")|\(current.operatingSystemVersion)")

        let context = HealthKitConversionContext()
        let identifiers = try HealthKitConverter().convert(Self.heartRate, context: context).graphIdentifiers
        let scope = context.event.identityScope
        #expect(identifiers.applicationSnapshot == (try scope.deviceSnapshot(
            event: context.event.event,
            role: .application,
            sourceDeviceToken: application.sourceDeviceToken
        )))
        #expect(identifiers.hostSnapshot == (try scope.deviceSnapshot(
            event: context.event.event,
            role: .host,
            sourceDeviceToken: context.event.host.sourceDeviceToken
        )))
    }

    @Test("A subject states its pseudonym as its identifier however it travels")
    func subjectIdentifier() {
        let pseudonym = BusinessIdentifier.test(.patient, "example")
        #expect(Subject.logical(pseudonym).identifier == pseudonym)
        #expect(Subject.bundled(pseudonym, Patient()).identifier == pseudonym)
    }

    @Test("A study enrollment is flat: study, protocol URL and version, enrollment")
    func flatStudyEnrollment() {
        let enrollment = StudyEnrollment.test("study-1")
        #expect(enrollment.study == .test(.researchStudy, "study-1"))
        #expect(enrollment.protocolURL.value?.url.absoluteString == "https://study.example.org/PlanDefinition/study-1")
        #expect(enrollment.protocolVersion == "1")
        #expect(enrollment.enrollment == .test(.researchSubject, "enrollment-study-1"))
    }

    @Test("Retraction targets are typed and carry the native record identifier only under the disclosure policy")
    func retractionTargets() throws {
        let record = HealthKitSourceRecord(uuid: Self.heartRate.uuid, type: .heartRate)
        let omitted = try HealthKitConverter().retractionTargets(for: record, context: HealthKitConversionContext())
        #expect(omitted.map(\.resourceType) == [.observation])
        #expect(omitted.allSatisfy { $0.nativeRecordIdentifier == nil })

        let store: IdentifierSystem = "https://study.example.org/fhir/NamingSystem/healthkit-store"
        let context = HealthKitConversionContext(nativeIdentifierDisclosurePolicy: .authorized(system: store))
        let disclosed = try HealthKitConverter().retractionTargets(for: record, context: context)
        let native = try BusinessIdentifier(system: store, value: Self.heartRate.uuid.uuidString.lowercased())
        #expect(disclosed.map(\.nativeRecordIdentifier) == [native])
        #expect(disclosed.map(\.identifier) == omitted.map(\.identifier))

        let sourceRecord = try context.event.identityScope.sourceRecord(
            adapterID: HealthKitConverter.adapterID,
            sourceType: HealthKitSourceType.heartRate.rawValue,
            repositoryScope: context.event.repositoryScope,
            nativeRecordID: native.value
        ).identifier
        let graph = try RetractionEvent(
            targets: disclosed,
            context: context.event,
            sourceRecord: sourceRecord,
            retractedAt: ExchangeEventContext.testInstant
        ).graph
        let provenance = try #require(graph.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let rendered = provenance.target.first?.extension?.first { $0.url == Canonicals.retractionTargetNativeIdentifier }
        #expect(rendered?.value == .identifier(native.fhirIdentifier))
        #expect(graph.bundle.timestamp?.value?.description == "2026-08-17T23:30:00Z")
        #expect(provenance.recorded.value?.description == "2026-08-17T23:30:00Z")
        #expect(provenance.occurred == .dateTime(FHIRPrimitive(try DateTime("2026-08-17T23:30:00Z"))))

        let reserved = HealthKitConversionContext(
            nativeIdentifierDisclosurePolicy: .authorized(system: context.event.identityScope.systems.opaque.sourceOutput)
        )
        #expect(throws: HealthKitConversionError.reservedIdentifierSystem) {
            try HealthKitConverter().retractionTargets(for: record, context: reserved)
        }
    }
}


/// The shared protocol vectors, read from the grove-fhir working tree.
@Suite(.enabled(if: groveFHIRIsAvailable, "Requires the grove-fhir checkout used by FHIR Output Conformance"))
struct ProducerContractVectorTests {
    private struct Catalog: Decodable {
        struct IdentitySystem: Decodable {
            let identityKind: String
            let system: String
        }

        struct Identity: Decodable {
            let id: String
            let identityKind: String
            let components: [String]
            let value: String
        }

        struct InvalidIdentity: Decodable {
            let id: String
            let identityKind: String
            let components: [String]
            let expectedError: String
        }

        struct System: Decodable {
            let system: String
        }

        struct Vectors: Decodable {
            let keyId: String
            let epoch: String
            let identitySystems: [IdentitySystem]
            let identities: [Identity]
            let invalidIdentities: [InvalidIdentity]
            let event: System
            let entryNode: System
        }

        struct Diagnostic: Decodable {
            let code: String
            let reason: String
            let severity: ProducerDiagnostic.Severity?
        }

        struct IdentityKind: Decodable {
            let kind: String
            let components: [String]
        }

        struct OpaqueIdentity: Decodable {
            let identityKinds: [IdentityKind]
        }

        let testVectors: Vectors
        let producerDiagnostics: [Diagnostic]
        let opaqueIdentity: OpaqueIdentity
    }

    private static let deploymentRoot: IdentifierSystem = "https://study.example.org/fhir"

    private static var catalog: Catalog {
        get throws {
            try JSONDecoder().decode(
                Catalog.self,
                from: Data(contentsOf: groveFHIRRoot.appendingPathComponent("catalog/exchange-protocol.json"))
            )
        }
    }

    private static func scope(_ vectors: Catalog.Vectors) throws -> OpaqueIdentityScope {
        let epoch = try EventSequence(vectors.epoch)
        let systems = try DeploymentIdentifierSystems.derived(root: deploymentRoot, keyID: vectors.keyId, epoch: epoch)
        return try OpaqueIdentityScope.conformanceTesting(systems: systems, keyID: vectors.keyId, epoch: epoch)
    }

    private static func identity(
        _ scope: OpaqueIdentityScope,
        kind: OpaqueIdentityKind,
        components: [String]
    ) throws -> RoledIdentifier {
        func identifier(_ system: String, _ value: String) throws -> BusinessIdentifier {
            try BusinessIdentifier(system: IdentifierSystem(system), value: value)
        }
        func sourceRecord() throws -> SourceRecordIdentity {
            try scope.sourceRecord(
                adapterID: components[0],
                sourceType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeRecordID: components[4]
            )
        }
        func providerRecord() throws -> ProviderRecordIdentity {
            try scope.providerRecord(
                providerCode: #require(GroveProviderCode(rawValue: components[0]), "\(components[0])"),
                sourceType: components[1],
                providerScope: identifier(components[2], components[3]),
                nativeRecordID: components[4]
            )
        }
        switch kind {
        case .sourceRecord:
            return try sourceRecord().identifier
        case .sourceOutput:
            return try sourceRecord().output(role: components[5], discriminator: components[6])
        case .sourceArtifact:
            return try sourceRecord().artifact(formatCode: components[5], partIndex: CanonicalNonnegativeDecimal(components[6]))
        case .providerRecord:
            return try providerRecord().identifier
        case .providerOutput:
            return try providerRecord().output(role: components[5], discriminator: components[6])
        case .providerArtifact:
            return try providerRecord().artifact(formatCode: components[5], partIndex: CanonicalNonnegativeDecimal(components[6]))
        case .writerRecord:
            return try scope.writerRecord(
                writerApplication: identifier(components[0], components[1]),
                writerRecordID: components[2]
            )
        case .sourceContext:
            return try scope.sourceContext(
                adapterID: components[0],
                contextType: components[1],
                repositoryScope: identifier(components[2], components[3]),
                nativeContextID: components[4]
            )
        case .recordingDevice:
            return try scope.recordingDevice(
                adapterID: components[0],
                subject: identifier(components[1], components[2]),
                stableUnitToken: components[3]
            )
        case .deviceSnapshot:
            return try scope.deviceSnapshot(
                event: ExchangeEventIdentifier(identifier(components[0], components[1])),
                role: #require(DeviceSnapshotRole(rawValue: components[2]), "\(components[2])"),
                sourceDeviceToken: components[3]
            )
        }
    }

    @Test("Derived identifier systems equal the shared vectors")
    func derivedSystemsMatchVectors() throws {
        let vectors = try Self.catalog.testVectors
        let epoch = try EventSequence(vectors.epoch)
        let derived = try DeploymentIdentifierSystems.derived(root: Self.deploymentRoot, keyID: vectors.keyId, epoch: epoch)
        #expect(vectors.identitySystems.count == OpaqueIdentityKind.allCases.count)
        for vector in vectors.identitySystems {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind))
            #expect(derived.opaque[kind].rawValue == vector.system, "\(vector.identityKind)")
        }
        #expect(derived.event.rawValue == vectors.event.system)
        #expect(derived.entryNode.rawValue == vectors.entryNode.system)
        #expect(try DeploymentIdentifierSystems.derived(root: "https://study.example.org/fhir/", keyID: vectors.keyId, epoch: epoch) == derived)
        #expect(throws: ExchangeIdentityError.invalidKeyID("bad key")) {
            try DeploymentIdentifierSystems.derived(root: Self.deploymentRoot, keyID: "bad key", epoch: epoch)
        }
    }

    @Test("Every shared identity vector is reproduced token for token")
    func identityVectors() throws {
        let vectors = try Self.catalog.testVectors
        let scope = try Self.scope(vectors)
        for vector in vectors.identities {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind), "\(vector.id)")
            let identity = try Self.identity(scope, kind: kind, components: vector.components)
            #expect(identity.value == vector.value, "\(vector.id)")
            #expect(identity.system == scope.systems.opaque[kind], "\(vector.id)")
        }
    }

    @Test("Application and host tokens take the vectors' form and mint the vectors' snapshots")
    func deviceTokenVectors() throws {
        let vectors = try Self.catalog.testVectors
        let scope = try Self.scope(vectors)
        let tokens = [
            "device-snapshot-per-event": try ApplicationDevice(name: "Example", bundleIdentifier: "com.example.app", version: "1.2.3")
                .sourceDeviceToken,
            "questionnaire-extraction-application-snapshot": try ApplicationDevice(
                name: "Grove Questionnaire Client",
                bundleIdentifier: "org.grovealliance.example.client",
                version: "1.4.0",
                build: "1402"
            ).sourceDeviceToken,
            "questionnaire-extraction-host-snapshot": try HostDevice(operatingSystemVersion: "26.0", modelNumber: "iPhone17,1")
                .sourceDeviceToken
        ]
        for (id, token) in tokens {
            let vector = try #require(vectors.identities.first { $0.id == id }, "\(id)")
            #expect(token == vector.components[3], "\(id)")
            let event = try ExchangeEventIdentifier(BusinessIdentifier(
                system: IdentifierSystem(vector.components[0]),
                value: vector.components[1]
            ))
            let role = try #require(DeviceSnapshotRole(rawValue: vector.components[2]))
            #expect(try scope.deviceSnapshot(event: event, role: role, sourceDeviceToken: token).value == vector.value, "\(id)")
        }
    }

    @Test("Every shared invalid identity vector is refused for its stated reason")
    func invalidIdentityVectors() throws {
        let catalog = try Self.catalog
        let vectors = catalog.testVectors
        let scope = try Self.scope(vectors)
        for vector in vectors.invalidIdentities {
            let kind = try #require(OpaqueIdentityKind(rawValue: vector.identityKind), "\(vector.id)")
            switch vector.expectedError {
            case "empty-component":
                let names = try #require(catalog.opaqueIdentity.identityKinds.first { $0.kind == kind.rawValue }?.components)
                let path = "\(kind.rawValue).\(names[try #require(vector.components.firstIndex(of: ""))])"
                #expect(throws: OpaqueIdentityError.emptyComponent(path), "\(vector.id)") {
                    try scope.identifier(kind: kind, components: vector.components)
                }
            case "provider-kind-required":
                #expect(throws: OpaqueIdentityError.providerKindRequired(vector.components[0]), "\(vector.id)") {
                    try scope.identifier(kind: kind, components: vector.components)
                }
            case "non-canonical-part-index":
                #expect(throws: OpaqueIdentityError.nonCanonicalPartIndex("\(kind.rawValue).part-index"), "\(vector.id)") {
                    try scope.identifier(kind: kind, components: vector.components)
                }
            default:
                Issue.record("Unknown expected error \(vector.expectedError) for \(vector.id)")
            }
        }
    }

    @Test("An identity fault reports the same registry code on every platform")
    func identityFaultCodes() {
        let path = "source-artifact.part-index"
        let table: [(ProducerDiagnostic, ProducerDiagnostic)] = [
            (OpaqueIdentityError.emptyComponent(path).diagnostic, ExchangeGraphRule.mobileInputRequiredMetadataMissing.diagnostic(at: path)),
            (OpaqueIdentityError.nonCanonicalPartIndex(path).diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: path)),
            (
                ExchangeIdentityError.invalidEventIdentifier("e0:x").diagnostic,
                ExchangeGraphRule.mobileExchangeEventIdentity.diagnostic(at: "Bundle.identifier.value")
            ),
            (OpaqueIdentityError.keyTooShort(actualBytes: 16).diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic),
            (OpaqueIdentityError.invalidKeyID("").diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic),
            (OpaqueIdentityError.reusedIdentifierSystem.diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic),
            (ExchangeIdentityError.invalidIdentifierSystem("x").diagnostic, ExchangeGraphRule.mobileInputUnclassified.diagnostic)
        ]
        for (actual, expected) in table {
            #expect(actual == expected, "\(expected.code)")
        }
        let fault = OpaqueIdentityError.emptyComponent(path)
        #expect(HealthKitConversionError.opaqueIdentity(fault).diagnostic == fault.diagnostic)
    }

    @Test("Registry severities have not drifted")
    func registrySeverities() throws {
        let registry = Dictionary(uniqueKeysWithValues: try Self.catalog.producerDiagnostics.map { ($0.code, $0) })
        #expect(registry.count == ExchangeGraphRule.allCases.count)
        for rule in ExchangeGraphRule.allCases {
            let row = try #require(registry[rule.rawValue], "\(rule.rawValue)")
            #expect(row.severity ?? .error == rule.severity, "\(rule.rawValue)")
            #expect(row.reason == rule.diagnostic.reason, "\(rule.rawValue)")
        }
    }

    @Test("The study-attribution source event is a complete bundled study context")
    func studyAttributionSourceEvent() throws {
        let path = groveFHIRRoot.appendingPathComponent("Conformance/corpora/study-attribution/source-event.json")
        _ = try ExchangeGraph(kind: .active, jsonData: Data(contentsOf: path))
    }

    @Test("Receiver-lifecycle retries are compared over lossless JSON tokens")
    func equalityVectors() throws {
        struct Events: Decodable {
            struct Event: Decodable {
                let path: String
            }

            let events: [String: Event]
        }
        let corpus = groveFHIRRoot.appendingPathComponent(ExchangeContract.equalityVectorCorpus, isDirectory: true)
        let events = try JSONDecoder().decode(Events.self, from: Data(contentsOf: corpus.appendingPathComponent("events.json"))).events
        func graph(_ name: String, kind: ExchangeGraphKind = .active) throws -> ExchangeGraph {
            guard let event = events[name] else {
                throw MissingEvent(name: name)
            }
            return try ExchangeGraph(kind: kind, jsonData: Data(contentsOf: corpus.appendingPathComponent(event.path)))
        }
        let original = try graph("original")
        let reformatted = try graph(ExchangeContract.equalityFormattingVector)
        let lexeme = try graph(ExchangeContract.equalityDecimalLexemeVector)
        let altered = try graph("altered-retry")

        #expect(original.isSemanticallyEqual(to: original))
        #expect(original.isSemanticallyEqual(to: reformatted))
        #expect(reformatted.isSemanticallyEqual(to: original))
        #expect(!original.isSemanticallyEqual(to: lexeme))
        #expect(!original.isSemanticallyEqual(to: altered))
        #expect(original.eventIdentifier == reformatted.eventIdentifier)
        #expect(original.eventIdentifier == lexeme.eventIdentifier)

        let retraction = try graph("retraction", kind: .retraction)
        let provenance = try #require(retraction.bundle.entry?.compactMap { $0.resource?.get(if: Provenance.self) }.first)
        let targets = try provenance.target.map { try RoledIdentifier(#require($0.identifier)) }
        #expect(!targets.isEmpty)
        #expect(targets.allSatisfy { $0.role == .sourceOutput || $0.role == .deviceSnapshot })
    }
}

#endif

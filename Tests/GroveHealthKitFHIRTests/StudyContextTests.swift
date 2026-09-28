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


/// A known enrollment becomes a complete bundled study context, and a graph that loses any part of it is refused.
@Suite
struct StudyContextTests {
    private typealias Entries = [[String: Any]]

    private static let enrollments = [StudyEnrollment.test("a"), StudyEnrollment.test("b")]
    private static let studyContextRule = "mobile-support.study-context"

    private static let sample = HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
        start: ExchangeEventContext.testInstant,
        end: ExchangeEventContext.testInstant,
        metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]
    )

    private static func conversion(
        subject: Subject = .testPatient,
        studies: [StudyEnrollment] = enrollments
    ) throws -> HealthKitConversionSet {
        try HealthKitConverter().convert(sample, context: HealthKitConversionContext(subject: subject, studies: studies))
    }

    private static func graph(subject: Subject = .testPatient) throws -> ExchangeGraph {
        try conversion(subject: subject).primary.graph
    }

    private static func bundleObject(_ graph: ExchangeGraph) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(graph.bundle)) as? [String: Any])
    }

    private static func resources(_ entries: Entries, ofType type: String) -> [[String: Any]] {
        entries.compactMap { $0["resource"] as? [String: Any] }.filter { $0["resourceType"] as? String == type }
    }

    /// The diagnostic a re-parse reports after the entries are rewritten, or nil when the graph stays valid.
    private static func revalidate(_ graph: ExchangeGraph, rewriting: (Entries) throws -> Entries) throws -> ProducerDiagnostic? {
        var object = try bundleObject(graph)
        object["entry"] = try rewriting(try #require(object["entry"] as? Entries))
        let data = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try ExchangeGraph(kind: .active, jsonData: data)
            return nil
        } catch {
            return error.diagnostic
        }
    }

    private static func rewriting(_ entries: Entries, type: String, _ change: (inout [String: Any]) -> Void) -> Entries {
        entries.map { entry in
            guard var resource = entry["resource"] as? [String: Any], resource["resourceType"] as? String == type else {
                return entry
            }
            change(&resource)
            var entry = entry
            entry["resource"] = resource
            return entry
        }
    }

    @Test("Every enrollment becomes its study, plan and subject entries, and every output names the studies")
    func enrollmentBecomesStudyContext() throws {
        let graph = try Self.graph()
        let entries = try #require(try Self.bundleObject(graph)["entry"] as? Entries)
        #expect(Self.resources(entries, ofType: "ResearchStudy").count == 2)
        #expect(Self.resources(entries, ofType: "PlanDefinition").count == 2)
        #expect(Self.resources(entries, ofType: "ResearchSubject").count == 2)
        let plans = Self.resources(entries, ofType: "PlanDefinition")
        #expect(plans.allSatisfy { $0["url"] is String && $0["version"] as? String == "1" })
        let observation = try #require(Self.resources(entries, ofType: "Observation").first)
        let studyReferences = (observation["extension"] as? [[String: Any]] ?? []).filter {
            $0["url"] as? String == "http://hl7.org/fhir/StructureDefinition/workflow-researchStudy"
        }
        #expect(studyReferences.count == 2)
        #expect(try Self.revalidate(graph) { $0 } == nil)
    }

    @Test("A bundled subject is the Patient entry every ResearchSubject links to")
    func bundledSubjectIsThePatientEntry() throws {
        let graph = try Self.graph(subject: .bundled(.test(.patient, "example"), Patient()))
        let entries = try #require(try Self.bundleObject(graph)["entry"] as? Entries)
        let patient = try #require(entries.first { ($0["resource"] as? [String: Any])?["resourceType"] as? String == "Patient" })
        let patientURL = try #require(patient["fullUrl"] as? String)
        for subject in Self.resources(entries, ofType: "ResearchSubject") {
            #expect((subject["individual"] as? [String: Any])?["reference"] as? String == patientURL)
        }
        #expect(try Self.revalidate(graph) { $0 } == nil)
    }

    @Test("Study relevance leaves the measurement and its identities unchanged", arguments: [0, 1, 2])
    func studyRelevancePreservesTheMeasurement(studyCount: Int) throws {
        let baseline = try Self.conversion(studies: [])
        let conversion = try Self.conversion(studies: (0..<studyCount).map { StudyEnrollment.test("study-\($0)") })
        let studies = conversion.observation.extension?.filter { $0.url == Canonicals.researchStudy } ?? []
        #expect(studies.count == studyCount)
        #expect(conversion.observation.extension?.contains { $0.url == Canonicals.instantiatesCanonical } != true)
        #expect(conversion.observation.value == baseline.observation.value)
        #expect(conversion.observation.effective == baseline.observation.effective)
        #expect(conversion.graphIdentifiers == baseline.graphIdentifiers)
        #expect(conversion.provenance == baseline.provenance)
        #expect(conversion.bundle.identifier == baseline.bundle.identifier)
        let fullURLs = Set(conversion.bundle.entry?.compactMap(\.fullUrl) ?? [])
        let baselineURLs = Set(baseline.bundle.entry?.compactMap(\.fullUrl) ?? [])
        #expect(baselineURLs.isSubset(of: fullURLs))
        #expect(try Self.revalidate(conversion.primary.graph) { $0 } == nil)
    }

    @Test("Each enrollment keeps its own exact protocol revision")
    func enrollmentsKeepTheirOwnProtocolRevision() throws {
        let enrollments = try [("a", "2"), ("b", "4")].map { study, version in
            try StudyEnrollment(
                study: .test(.researchStudy, study),
                protocolURL: FHIRPrimitive(Canonical(stringLiteral: "https://study.example.org/PlanDefinition/\(study)")),
                protocolVersion: version,
                enrollment: .test(.researchSubject, "enrollment-\(study)")
            )
        }
        let entries = try #require(try Self.bundleObject(Self.conversion(studies: enrollments).primary.graph)["entry"] as? Entries)
        let plansByURL = Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (String, [String: Any])? in
            guard let resource = entry["resource"] as? [String: Any], resource["resourceType"] as? String == "PlanDefinition",
                  let fullURL = entry["fullUrl"] as? String else {
                return nil
            }
            return (fullURL, resource)
        })
        let revisions = Self.resources(entries, ofType: "ResearchStudy").compactMap { study -> String? in
            guard let reference = (study["protocol"] as? [[String: Any]])?.first?["reference"] as? String,
                  let plan = plansByURL[reference] else {
                return nil
            }
            return "\(plan["url"] as? String ?? "")|\(plan["version"] as? String ?? "")"
        }
        #expect(revisions == [
            "https://study.example.org/PlanDefinition/a|2",
            "https://study.example.org/PlanDefinition/b|4"
        ])
    }

    @Test("A retry of the persisted context rebuilds the same event, study context included")
    func retryPreservesTheStudyContext() throws {
        let original = try Self.graph()
        let retry = try Self.graph()
        #expect(original.eventIdentifier == retry.eventIdentifier)
        #expect(original.isSemanticallyEqual(to: retry))
        #expect(!original.isSemanticallyEqual(to: try Self.conversion(studies: [.test("a")]).primary.graph))
    }

    @Test("A study without its ResearchSubject is refused")
    func missingResearchSubjectIsRefused() throws {
        let diagnostic = try Self.revalidate(Self.graph()) { entries in
            entries.filter { ($0["resource"] as? [String: Any])?["resourceType"] as? String != "ResearchSubject" }
        }
        #expect(diagnostic == ExchangeGraphRule.mobileSupportStudyContext.diagnostic)
        #expect(diagnostic?.code == Self.studyContextRule)
    }

    @Test("A PlanDefinition without its exact version is refused")
    func unversionedPlanIsRefused() throws {
        let diagnostic = try Self.revalidate(Self.graph()) { entries in
            Self.rewriting(entries, type: "PlanDefinition") { $0["version"] = nil }
        }
        #expect(diagnostic?.code == Self.studyContextRule)
    }

    @Test("A ResearchStudy without its protocol is refused")
    func studyWithoutProtocolIsRefused() throws {
        let diagnostic = try Self.revalidate(Self.graph()) { entries in
            Self.rewriting(entries, type: "ResearchStudy") { $0["protocol"] = nil }
        }
        #expect(diagnostic?.code == Self.studyContextRule)
    }

    @Test("A ResearchSubject enrolling someone other than the graph's subject is refused")
    func foreignIndividualIsRefused() throws {
        let diagnostic = try Self.revalidate(Self.graph()) { entries in
            Self.rewriting(entries, type: "ResearchSubject") {
                $0["individual"] = [
                    "type": "Patient",
                    "identifier": ["system": "https://grovealliance.org/fhir/testing/identifiers/patient", "value": "someone-else"]
                ]
            }
        }
        #expect(diagnostic?.code == Self.studyContextRule)
    }
}

#endif

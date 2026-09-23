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

    private static func graph(subject: Subject = .testPatient) throws -> ExchangeGraph {
        let context = HealthKitConversionContext(subject: subject, studies: enrollments)
        let start = ExchangeEventContext.testInstant
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 72),
            start: start,
            end: start,
            metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles"]
        )
        return try HealthKitConverter().convert(sample, context: context).primary.graph
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

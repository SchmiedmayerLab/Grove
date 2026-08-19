//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct HKStateOfMindTests {
    @Test
    @available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
    func stateOfMind1() throws {
        let cal = Calendar.current
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now)))
        let sample = HKStateOfMind(
            date: yesterday,
            kind: .dailyMood,
            valence: 0.27,
            labels: [.indifferent],
            associations: [.work]
        )
        let observation = try #require(sample.resource(subject: Reference(reference: "Patient/example")).get(if: Observation.self))
        #expect(observation.effective == .dateTime(try FHIRPrimitive<DateTime>(.init(date: yesterday))))
        #expect(observation.category?.first?.coding?.first?.code == "survey")
        #expect(observation.status == .final)
        let components = try #require(observation.component)
        #expect(components.count == 5)
        components.expectContainsComponent(withCode: "kind", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "dailyMood".asFHIRStringPrimitive(),
                display: "daily mood".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-kind"
            )
        ])))
        components.expectContainsComponent(withCode: "valence", value: .quantity(Quantity(
            code: "1".asFHIRStringPrimitive(),
            system: "http://unitsofmeasure.org",
            unit: "score".asFHIRStringPrimitive(),
            value: 0.27.asFHIRDecimalPrimitive()
        )))
        components.expectContainsComponent(withCode: "valence-classification", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "slightlyPleasant".asFHIRStringPrimitive(),
                display: "slightly pleasant".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-valence-classification"
            )
        ])))
        components.expectContainsComponent(withCode: "label", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "indifferent".asFHIRStringPrimitive(),
                display: "indifferent".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-label"
            )
        ])))
        components.expectContainsComponent(withCode: "association", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "work".asFHIRStringPrimitive(),
                display: "work".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-association"
            )
        ])))
    }
    
    
    @Test
    @available(iOS 18.0, watchOS 11.0, macCatalyst 18.0, macOS 15.0, visionOS 2.0, *)
    func stateOfMind2() throws {
        let cal = Calendar.current
        let yesterday = try #require(cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now)))
        let sample = HKStateOfMind(
            date: yesterday,
            kind: .momentaryEmotion,
            valence: -0.52,
            labels: [.brave, .confident, .lonely],
            associations: [.dating, .community, .friends]
        )
        let observation = try #require(sample.resource(subject: Reference(reference: "Patient/example")).get(if: Observation.self))
        #expect(observation.effective == .dateTime(try FHIRPrimitive<DateTime>(.init(date: yesterday))))
        #expect(observation.category?.first?.coding?.first?.code == "survey")
        #expect(observation.status == .final)
        let components = try #require(observation.component)
        #expect(components.count == 9)
        components.expectContainsComponent(withCode: "kind", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "momentaryEmotion".asFHIRStringPrimitive(),
                display: "momentary emotion".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-kind"
            )
        ])))
        components.expectContainsComponent(withCode: "valence", value: .quantity(Quantity(
            code: "1".asFHIRStringPrimitive(),
            system: "http://unitsofmeasure.org",
            unit: "score".asFHIRStringPrimitive(),
            value: FHIRPrimitive(FHIRDecimal(-0.52))
        )))
        components.expectContainsComponent(withCode: "valence-classification", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "unpleasant".asFHIRStringPrimitive(),
                display: "unpleasant".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-valence-classification"
            )
        ])))
        components.expectContainsComponent(withCode: "label", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "brave".asFHIRStringPrimitive(),
                display: "brave".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-label"
            )
        ])))
        components.expectContainsComponent(withCode: "label", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "confident".asFHIRStringPrimitive(),
                display: "confident".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-label"
            )
        ])))
        components.expectContainsComponent(withCode: "label", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "lonely".asFHIRStringPrimitive(),
                display: "lonely".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-label"
            )
        ])))
        components.expectContainsComponent(withCode: "association", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "dating".asFHIRStringPrimitive(),
                display: "dating".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-association"
            )
        ])))
        components.expectContainsComponent(withCode: "association", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "community".asFHIRStringPrimitive(),
                display: "community".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-association"
            )
        ])))
        components.expectContainsComponent(withCode: "association", value: .codeableConcept(CodeableConcept(coding: [
            Coding(
                code: "friends".asFHIRStringPrimitive(),
                display: "friends".asFHIRStringPrimitive(),
                system: "https://grovealliance.org/fhir/platforms/CodeSystem/healthkit-state-of-mind-association"
            )
        ])))
    }
}


extension Array where Element == ObservationComponent {
    func expectContainsComponent(withCode code: String, value: ObservationComponent.ValueX?) {
        let candidates = self.filter { $0.code.coding?.contains { $0.code?.value?.string == code } == true }
        guard !candidates.isEmpty else {
            Issue.record("Unable to find a component for code '\(code)'.")
            return
        }
        if candidates.count == 1 {
            #expect(candidates[0].value == value, "Mismatching component values for code '\(code)'")
        } else {
            #expect(candidates.contains { $0.value == value }, "No component with matching value.")
        }
    }
}

#endif

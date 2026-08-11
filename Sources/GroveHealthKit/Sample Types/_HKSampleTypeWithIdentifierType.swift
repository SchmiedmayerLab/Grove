//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable type_name

#if canImport(HealthKit)
import HealthKit
#endif


/// An Identifier type used by a `HKSampleType` subclass
public protocol _HKSampleTypeIdentifierType: Hashable {
    init(rawValue: String)
}

extension HKQuantityTypeIdentifier: _HKSampleTypeIdentifierType {} // swiftlint:disable:this file_types_order
extension HKCorrelationTypeIdentifier: _HKSampleTypeIdentifierType {} // swiftlint:disable:this file_types_order
extension HKCategoryTypeIdentifier: _HKSampleTypeIdentifierType {} // swiftlint:disable:this file_types_order
@available(iOS 18, macOS 15, watchOS 11, *)
extension HKClinicalTypeIdentifier: _HKSampleTypeIdentifierType {} // swiftlint:disable:this file_types_order
extension HKScoredAssessmentTypeIdentifier: _HKSampleTypeIdentifierType {} // swiftlint:disable:this file_types_order


/// Associates a `HKSampleType` subclass with its corresponding identifier type.
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol _HKSampleTypeWithIdentifierType: HKSampleType {
    associatedtype _Identifier: _HKSampleTypeIdentifierType
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HKQuantityType: _HKSampleTypeWithIdentifierType {
    public typealias _Identifier = HKQuantityTypeIdentifier
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCorrelationType: _HKSampleTypeWithIdentifierType {
    public typealias _Identifier = HKCorrelationTypeIdentifier
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension HKCategoryType: _HKSampleTypeWithIdentifierType {
    public typealias _Identifier = HKCategoryTypeIdentifier
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension HKClinicalType: _HKSampleTypeWithIdentifierType {
    public typealias _Identifier = HKClinicalTypeIdentifier
}

@available(iOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *)
extension HKScoredAssessmentType: _HKSampleTypeWithIdentifierType {
    public typealias _Identifier = HKScoredAssessmentTypeIdentifier
}

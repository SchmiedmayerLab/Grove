//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import SpeziHealthKit
public import SpeziHealthKitBulkExport


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition {
    /// Study Component which initiates background Health data collection
    public struct HealthDataCollectionComponent: Identifiable, StudyDefinitionElement {
        /// Defines a ``StudyDefinition/HealthDataCollectionComponent``'s collection of historical Health data.
        public enum HistoricalDataCollection: StudyDefinitionElement {
            /// The component should not collect historical data, i.e. should limit its collection only to new data added to the Health Store.
            case disabled
            /// The component should, in addition to collecting new data added to the Health Store,
            /// also collect historical data, starting at the specified start date.
            case enabled(ExportSessionStartDate)
        }
        public var id: UUID
        /// The sample types that should be collected when enrolled in the study.
        public var sampleTypes: SampleTypesCollection
        /// Additional, optional sample types that should be collected when enrolled in the study.
        ///
        /// The difference between optional sample types defined via this property and those sample types defined via the ``sampleTypes`` property
        /// is that SpeziStudy will not prompt the user for authorization to access any of the optional sample types.
        /// Instead, they will only be included in the data collection if the user has already granted read access.
        /// This allows the app to control when and how the user should be prompted for authorization.
        public var optionalSampleTypes: SampleTypesCollection
        public var historicalDataCollection: HistoricalDataCollection
        
        public init(
            id: UUID,
            sampleTypes: SampleTypesCollection,
            optionalSampleTypes: SampleTypesCollection,
            historicalDataCollection: HistoricalDataCollection
        ) {
            self.id = id
            self.sampleTypes = sampleTypes
            self.optionalSampleTypes = optionalSampleTypes
            self.historicalDataCollection = historicalDataCollection
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension StudyDefinition.HealthDataCollectionComponent {
    private enum CodingKeys: CodingKey {
        case id
        case sampleTypes
        case historicalDataCollection
        case optionalSampleTypes
    }
    
    // swiftlint:disable:next missing_docs
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sampleTypes = try container.decode(SampleTypesCollection.self, forKey: .sampleTypes)
        historicalDataCollection = try container.decode(HistoricalDataCollection.self, forKey: .historicalDataCollection)
        optionalSampleTypes = try container.decodeIfPresent(SampleTypesCollection.self, forKey: .optionalSampleTypes) ?? []
    }
    
    // swiftlint:disable:next missing_docs
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sampleTypes, forKey: .sampleTypes)
        try container.encode(historicalDataCollection, forKey: .historicalDataCollection)
        try container.encode(optionalSampleTypes, forKey: .optionalSampleTypes)
    }
}

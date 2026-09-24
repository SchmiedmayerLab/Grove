//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsDSTU2
public import ModelsR4


/// Represents a FHIR (Fast Healthcare Interoperability Resources) entity.
///
/// Handles both DSTU2 and R4 versions, providing a unified interface to interact with different FHIR versions.
public struct FHIRResource: Identifiable, Hashable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case missingStableIdentity(resourceType: String)
        case invalidIdentityValue(String)
        case invalidBundleFullURL(String)
    }

    /// A resource key that is stable and collision-free across supported FHIR versions and types.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        public enum FHIRVersion: String, Hashable, Sendable {
            case r4 // swiftlint:disable:this identifier_name
            case dstu2
        }

        public enum Source: Hashable, Sendable {
            case logicalID(String)
            case bundleFullURL(String)
            case explicit(String)
        }

        public let version: FHIRVersion
        public let resourceType: String
        public let source: Source

        public var description: String {
            let sourceDescription = switch source {
            case .logicalID(let value): "id:\(value)"
            case .bundleFullURL(let value): "fullUrl:\(value)"
            case .explicit(let value): "explicit:\(value)"
            }
            return "\(version.rawValue)/\(resourceType)/\(sourceDescription)"
        }
    }

    /// Caller-provided identity for a resource whose wire representation intentionally has no
    /// `Resource.id`. Bundle ingestion uses `bundleFullURL`; standalone callers use `explicit`.
    public enum IdentitySource: Hashable, Sendable {
        case bundleFullURL(String)
        case explicit(String)
    }

    /// Version-specific FHIR resources.
    public enum VersionedFHIRResource: Hashable, Sendable {
        /// R4 version of FHIR resources.
        case r4(any ModelsR4.Resource) // swiftlint:disable:this identifier_name
        /// DSTU2 version of FHIR resources.
        case dstu2(any ModelsDSTU2.Resource)
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.r4(lhs), .r4(rhs)):
                lhs.isEqual(rhs)
            case let (.dstu2(lhs), .dstu2(rhs)):
                lhs.isEqual(rhs)
            case (.r4, .dstu2), (.dstu2, .r4):
                false
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .r4(let resource):
                hasher.combine(0)
                resource.hash(into: &hasher)
            case .dstu2(let resource):
                hasher.combine(1)
                resource.hash(into: &hasher)
            }
        }
    }
    
    /// The version-specific FHIR resource.
    public let versionedResource: VersionedFHIRResource
    /// Human-readable name or description of the resource.
    public let displayName: String
    public let id: ID
    
    /// The `id` of the underlying FHIR `Resource`.
    public var fhirId: String? {
        switch versionedResource {
        case let .r4(resource):
            resource.id?.value?.string
        case let .dstu2(resource):
            resource.id?.value?.string
        }
    }

    /// The type of the FHIR resource represented as a string. It provides an easy way to identify the kind of FHIR entity (e.g., Observation, MedicationOrder).
    public var resourceType: String {
        switch versionedResource {
        case let .r4(resource):
            return ResourceProxy(with: resource).resourceType
        case let .dstu2(resource):
            return ResourceProxy(with: resource).resourceType
        }
    }
    
    /// JSON representation of the FHIR resource with specified formatting. Useful for serialization and debugging.
    public var jsonDescription: String {
        get throws {
            try json(withConfiguration: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
    }

    package var nonLogicalIdentitySource: IdentitySource? {
        switch id.source {
        case .logicalID:
            nil
        case .bundleFullURL(let value):
            .bundleFullURL(value)
        case .explicit(let value):
            .explicit(value)
        }
    }
    
    
    /// Initializes a `FHIRResource` with a versioned FHIR resource and a display name.
    /// - Parameters:
    ///   - versionedResource: The specific version (DSTU2 or R4) of the FHIR resource.
    ///   - displayName: A user-friendly name for the resource.
    ///   - identitySource: A stable bundle full URL or caller-defined identity used when the resource has no logical id.
    public init(
        versionedResource: VersionedFHIRResource,
        displayName: String,
        identitySource: IdentitySource? = nil
    ) throws(ValidationError) {
        let version: ID.FHIRVersion
        let resourceType: String
        let logicalID: String?
        switch versionedResource {
        case .r4(let resource):
            version = .r4
            resourceType = ModelsR4.ResourceProxy(with: resource).resourceType
            logicalID = resource.id?.value?.string
        case .dstu2(let resource):
            version = .dstu2
            resourceType = ModelsDSTU2.ResourceProxy(with: resource).resourceType
            logicalID = resource.id?.value?.string
        }

        let source: ID.Source
        if let logicalID, !logicalID.isEmpty {
            try Self.validateIdentityValue(logicalID)
            source = .logicalID(logicalID)
        } else {
            switch identitySource {
            case .bundleFullURL(let value):
                try Self.validateIdentityValue(value)
                guard let url = URL(string: value), url.scheme != nil else {
                    throw .invalidBundleFullURL(value)
                }
                source = .bundleFullURL(value)
            case .explicit(let value):
                try Self.validateIdentityValue(value)
                source = .explicit(value)
            case nil:
                throw .missingStableIdentity(resourceType: resourceType)
            }
        }
        self.versionedResource = versionedResource
        self.displayName = displayName
        self.id = ID(version: version, resourceType: resourceType, source: source)
    }
    
    /// Convenience initializer for R4 version of FHIR resources.
    /// - Parameters:
    ///   - resource: An R4 FHIR resource.
    ///   - displayName: A user-friendly name for the resource.
    ///   - identitySource: A stable bundle full URL or caller-defined identity used when the resource has no logical id.
    public init(
        resource: any ModelsR4.Resource,
        displayName: String,
        identitySource: IdentitySource? = nil
    ) throws(ValidationError) {
        try self.init(versionedResource: .r4(resource), displayName: displayName, identitySource: identitySource)
    }
    
    /// Convenience initializer for DSTU2 version of FHIR resources.
    /// - Parameters:
    ///   - resource: A DSTU2 FHIR resource.
    ///   - displayName: A user-friendly name for the resource.
    ///   - identitySource: A stable bundle full URL or caller-defined identity used when the resource has no logical id.
    public init(
        resource: any ModelsDSTU2.Resource,
        displayName: String,
        identitySource: IdentitySource? = nil
    ) throws(ValidationError) {
        try self.init(versionedResource: .dstu2(resource), displayName: displayName, identitySource: identitySource)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    private static func validateIdentityValue(_ value: String) throws(ValidationError) {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw .invalidIdentityValue(value)
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Whether both wrappers carry the same complete resource and presentation value.
    package func hasSameContents(as other: Self) -> Bool {
        id == other.id
            && versionedResource == other.versionedResource
            && displayName == other.displayName
    }

    /// Generates a JSON string representation of the resource with specified formatting options.
    /// - Parameter outputFormatting: JSON encoding options such as pretty printing.
    /// - Returns: A JSON string representing the resource.
    public func json(withConfiguration outputFormatting: JSONEncoder.OutputFormatting) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        switch versionedResource {
        case let .r4(resource):
            return String(decoding: try encoder.encode(resource), as: UTF8.self)
        case let .dstu2(resource):
            return String(decoding: try encoder.encode(resource), as: UTF8.self)
        }
    }
}


extension FHIRResource {
    /// The underlying R4 resource, if applicable
    public var r4: (any ModelsR4.Resource)? { // swiftlint:disable:this identifier_name
        switch versionedResource {
        case .r4(let resource):
            resource
        case .dstu2:
            nil
        }
    }
    
    /// The underlying DSTU2 resource, if applicable
    public var dstu2: (any ModelsDSTU2.Resource)? {
        switch versionedResource {
        case .dstu2(let resource):
            resource
        case .r4:
            nil
        }
    }
}

extension Equatable {
    fileprivate func isEqual(_ other: Any) -> Bool {
        if let other = other as? Self {
            self == other
        } else {
            false
        }
    }
}

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import Foundation
public import Grove
public import struct ModelsR4.Bundle
public import Observation


/// In-memory datastore to manage FHIR resources grouped into automatically computed and updated categories.
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class FHIRStore: Module, DefaultInitializable, Sendable {
    public enum StoreError: Error, Equatable, Sendable {
        case duplicateIdentity(FHIRResource.ID)
        case duplicateBundleFullURL(String)
        case invalidBundleFullURL(entry: Int, value: String?)
        case unrecognizedResource(entry: Int)
        case invalidResource(entry: Int, FHIRResource.ValidationError)
    }

    /// The actual ``FHIRResource``s held by the ``FHIRStore``
    ///
    /// The `_resources` property needs to be marked with `@ObservationIgnored` to prevent changes to it
    /// from triggering updates to all computed properties.
    /// Instead, we explicitly control change notifications through `willSet`/`didSet` calls
    /// with specific keyPaths in the `insert`, `remove`, and other mutation methods.
    /// This ensures that only observers of the relevant category (e.g., observations, conditions) are notified when
    /// resources of that category are modified.
    /// See also the `mutatingResourceCategories` function
    @ObservationIgnored @MainActor @usableFromInline var _resources: Set<FHIRResource> = [] // swiftlint:disable:this identifier_name
    
    /// Create an empty ``FHIRStore``.
    public required init() {}
}


#if canImport(SwiftUI)
@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore: EnvironmentAccessible {}
#endif


// MARK: FHIRStore Resource Accessors

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore {
    /// `FHIRResource`s with category `allergyIntolerance`.
    @MainActor public var allergyIntolerances: Set<FHIRResource> {
        access(keyPath: \.allergyIntolerances)
        return _resources.filter { $0.category == .allergyIntolerance }
    }
    
    /// `FHIRResource`s with category `condition`.
    @MainActor public var conditions: Set<FHIRResource> {
        access(keyPath: \.conditions)
        return _resources.filter { $0.category == .condition }
    }
    
    /// `FHIRResource`s with category `diagnostic`.
    @MainActor public var diagnostics: Set<FHIRResource> {
        access(keyPath: \.diagnostics)
        return _resources.filter { $0.category == .diagnostic }
    }
    
    /// `FHIRResource`s with category `documentReference`.
    @MainActor public var documents: Set<FHIRResource> {
        access(keyPath: \.documents)
        return _resources.filter { $0.category == .document }
    }
    
    /// `FHIRResource`s with category `encounter`.
    @MainActor public var encounters: Set<FHIRResource> {
        access(keyPath: \.encounters)
        return _resources.filter { $0.category == .encounter }
    }
    
    /// `FHIRResource`s with category `immunization`
    @MainActor public var immunizations: Set<FHIRResource> {
        access(keyPath: \.immunizations)
        return _resources.filter { $0.category == .immunization }
    }
    
    /// `FHIRResource`s with category `medication`.
    @MainActor public var medications: Set<FHIRResource> {
        access(keyPath: \.medications)
        return _resources.filter { $0.category == .medication }
    }
    
    /// `FHIRResource`s with category `observation`.
    @MainActor public var observations: Set<FHIRResource> {
        access(keyPath: \.observations)
        return _resources.filter { $0.category == .observation }
    }
    
    /// `FHIRResource`s with category `procedure`.
    @MainActor public var procedures: Set<FHIRResource> {
        access(keyPath: \.procedures)
        return _resources.filter { $0.category == .procedure }
    }
    
    /// `FHIRResource`s with category `other`.
    @MainActor public var otherResources: Set<FHIRResource> {
        access(keyPath: \.otherResources)
        return _resources.filter { $0.category == .other }
    }
}


// MARK: FHIRStore Resource Insertion

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore {
    private static func resources(in bundle: ModelsR4.Bundle) throws(StoreError) -> [FHIRResource] {
        var resources: [FHIRResource] = []
        var fullURLs: Set<String> = []
        var identities: Set<FHIRResource.ID> = []
        for (index, entry) in (bundle.entry ?? []).enumerated() {
            guard let proxy = entry.resource else {
                continue
            }
            let fullURL: String?
            if let primitive = entry.fullUrl {
                guard let value = primitive.value?.url.absoluteString,
                      !value.isEmpty,
                      let parsed = URL(string: value),
                      parsed.scheme != nil else {
                    throw .invalidBundleFullURL(entry: index, value: primitive.value?.url.absoluteString)
                }
                guard fullURLs.insert(value).inserted else {
                    throw .duplicateBundleFullURL(value)
                }
                fullURL = value
            } else {
                fullURL = nil
            }
            if case .unrecognized = proxy {
                throw .unrecognizedResource(entry: index)
            }
            let resource: FHIRResource
            do {
                resource = try FHIRResource(
                    resource: proxy.get(),
                    displayName: proxy.displayName,
                    identitySource: fullURL.map(FHIRResource.IdentitySource.bundleFullURL)
                )
            } catch {
                throw .invalidResource(entry: index, error)
            }
            guard identities.insert(resource.id).inserted else {
                throw .duplicateIdentity(resource.id)
            }
            resources.append(resource)
        }
        return resources
    }

    /// Inserts or replaces a FHIR resource by stable identity.
    ///
    /// - parameter resource: The `FHIRResource` to be inserted.
    /// - returns: `true` when the store changed; `false` when the same identity already carried
    ///   byte-for-byte equivalent resource and presentation content.
    @MainActor
    @discardableResult
    public func insert(_ resource: FHIRResource) -> Bool {
        let previous = _resources.first { $0.id == resource.id }
        guard previous?.hasSameContents(as: resource) != true else {
            return false
        }
        let categories = [previous?.category, resource.category].compactMap { $0 }
        return mutatingResourceCategories(categories) {
            _resources.update(with: resource)
            return true
        }
    }
    
    /// Inserts multiple ``FHIRResource``s into the store.
    ///
    /// - Parameter resourcesToInsert: The `FHIRResource`s to be inserted.
    @MainActor
    public func insert(contentsOf resourcesToInsert: some Sequence<FHIRResource>) throws(StoreError) {
        let resourcesToInsert = Array(resourcesToInsert)
        var identities: Set<FHIRResource.ID> = []
        for resource in resourcesToInsert where !identities.insert(resource.id).inserted {
            throw .duplicateIdentity(resource.id)
        }
        let changed = resourcesToInsert.filter { candidate in
            !_resources.contains { $0.hasSameContents(as: candidate) }
        }
        guard !changed.isEmpty else {
            return
        }
        let replacedCategories = changed.compactMap { candidate in
            _resources.first { $0.id == candidate.id }?.category
        }
        mutatingResourceCategories(changed.map(\.category) + replacedCategories) {
            for resource in changed {
                _resources.update(with: resource)
            }
        }
    }
    
    /// Loads resources from a given FHIR `Bundle` into the ``FHIRStore``.
    ///
    /// - Parameter bundle: The FHIR `Bundle` containing resources to be loaded.
    @MainActor
    public func load(bundle: ModelsR4.Bundle) throws {
        try insert(contentsOf: Self.resources(in: bundle))
    }

    /// Validates a complete bundle before replacing the store, so one malformed resource cannot
    /// leave a half-updated patient selection.
    @MainActor
    public func replaceContents(with bundle: ModelsR4.Bundle) throws {
        let resources = try Self.resources(in: bundle)
        let replacement = Set(resources)
        let categories = _resources.map(\.category) + replacement.map(\.category)
        mutatingResourceCategories(categories) {
            _resources = replacement
        }
    }
}


// MARK: FHIRStore Resource Removal

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore {
    /// Removes a FHIR resource from the ``FHIRStore``.
    ///
    /// - Parameter id: The composite stable identity of the resource that should be removed.
    /// - returns: The removed ``FHIRResource``, if applicable.
    @MainActor
    @discardableResult
    public func removeResource(withID id: FHIRResource.ID) -> FHIRResource? {
        guard let resource = _resources.first(where: { $0.id == id }) else {
            return nil
        }
        return mutatingResourceCategories(CollectionOfOne(resource.category)) {
            _resources.remove(resource)
        }
    }
    
    /// Removes all ``FHIRResource``s that satisfy the predicate.
    @MainActor
    public func removeAllResources(where predicate: (FHIRResource) throws -> Bool) rethrows {
        let resourcesToRemove = try _resources.filter(predicate)
        guard !resourcesToRemove.isEmpty else {
            return
        }
        mutatingResourceCategories(resourcesToRemove.lazy.map(\.category)) {
            _resources.subtract(resourcesToRemove)
        }
    }
    
    /// Removes all resources from the ``FHIRStore``.
    @MainActor
    public func removeAllResources() {
        removeAllResources { _ in true }
    }
}


// MARK: FHIRStore Helpers

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore {
    @MainActor
    private func mutatingResourceCategories<Result>(
        _ categories: some Sequence<FHIRResource.FHIRResourceCategory>,
        _ operation: () -> Result
    ) -> Result {
        let categories = Array(Set(categories))
        for category in categories {
            _$observationRegistrar.willSet(self, keyPath: category.storeKeyPath)
        }
        let result = operation()
        for category in categories.reversed() {
            _$observationRegistrar.didSet(self, keyPath: category.storeKeyPath)
        }
        return result
    }
}


// MARK: FHIRStore + Collection

@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRStore: @MainActor Collection {
    public typealias Element = FHIRResource
    
    public struct Index: Comparable {
        @usableFromInline let _index: Set<FHIRResource>.Index // swiftlint:disable:this identifier_name
        
        @inlinable
        init(_ index: Set<FHIRResource>.Index) {
            _index = index
        }
        
        @inlinable
        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs._index < rhs._index
        }
    }
    
    
    @MainActor @inlinable public var isEmpty: Bool {
        _resources.isEmpty
    }
    
    @MainActor @inlinable public var startIndex: Index {
        Index(_resources.startIndex)
    }
    
    @MainActor @inlinable public var endIndex: Index {
        Index(_resources.endIndex)
    }
    
    @MainActor
    @inlinable
    public func _customContainsEquatableElement( // swiftlint:disable:this identifier_name
        _ element: FHIRResource
    ) -> Bool? { // swiftlint:disable:this discouraged_optional_boolean
        _resources.contains(element)
    }
    
    @MainActor
    @inlinable
    public func index(after idx: Index) -> Index {
        Index(_resources.index(after: idx._index))
    }
    
    @MainActor
    @inlinable
    public subscript(position: Index) -> FHIRResource {
        _resources[position._index]
    }
}

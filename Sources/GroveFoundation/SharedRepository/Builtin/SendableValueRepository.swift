//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A Sendable Shared Repository.
public struct SendableValueRepository<Anchor> {
    private var storage: [ObjectIdentifier: any AnyRepositoryValue & Sendable] = [:]


    /// Initializes an empty shared repository.
    public init() {}
}


extension SendableValueRepository: SendableSharedRepository {
    public func get<Source: KnowledgeSource<Anchor>>(_ source: Source.Type) -> Source.Value? where Source.Value: Sendable {
        (storage[ObjectIdentifier(source)] as? RepositoryValue<Source>)?.value
    }

    public mutating func set<Source: KnowledgeSource<Anchor>>(_ source: Source.Type, value newValue: Source.Value?) where Source.Value: Sendable {
        storage[ObjectIdentifier(source)] = newValue.map { RepositoryValue<Source>($0) }
    }

    public func collect<Value>(allOf type: Value.Type) -> [Value] {
        storage.values.compactMap { value in
            value.anyValue as? Value
        }
    }
}


extension SendableValueRepository: Collection {
    public typealias Index = Dictionary<ObjectIdentifier, any AnyRepositoryValue & Sendable>.Index

    public var startIndex: Index {
        storage.values.startIndex
    }

    public var endIndex: Index {
        storage.values.endIndex
    }

    public func index(after index: Index) -> Index {
        storage.values.index(after: index)
    }


    public subscript(position: Index) -> any AnyRepositoryValue & Sendable {
        storage.values[position]
    }
}

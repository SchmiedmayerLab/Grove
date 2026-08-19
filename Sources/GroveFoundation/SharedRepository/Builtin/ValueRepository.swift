//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// A Shared Repository.
public struct ValueRepository<Anchor> {
    private var storage: [ObjectIdentifier: any AnyRepositoryValue] = [:]


    /// Initializes an empty shared repository.
    public init() {}
}


extension ValueRepository: SharedRepository {
    public func get<Source: KnowledgeSource<Anchor>>(_ source: Source.Type) -> Source.Value? {
        (storage[ObjectIdentifier(source)] as? RepositoryValue<Source>)?.value
    }

    public mutating func set<Source: KnowledgeSource<Anchor>>(_ source: Source.Type, value newValue: Source.Value?) {
        self.storage[ObjectIdentifier(source)] = newValue.map { RepositoryValue<Source>($0) }
    }

    public func collect<Value>(allOf type: Value.Type) -> [Value] {
        storage.values.compactMap { value in
            value.anyValue as? Value
        }
    }
}


extension ValueRepository: Collection {
    public typealias Index = Dictionary<ObjectIdentifier, any AnyRepositoryValue>.Index

    public var startIndex: Index {
        storage.values.startIndex
    }

    public var endIndex: Index {
        storage.values.endIndex
    }

    public func index(after index: Index) -> Index {
        storage.values.index(after: index)
    }


    public subscript(position: Index) -> any AnyRepositoryValue {
        storage.values[position]
    }
}

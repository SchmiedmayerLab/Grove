//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Reports skipped partitions only after the accepted devices have finished yielding batches.
@available(iOS 18, macOS 15, watchOS 11, *)
struct DevicePartitionIterator<Base: AsyncIteratorProtocol>: AsyncIteratorProtocol {
    typealias Element = Base.Element
    typealias Failure = any Error

    var base: Base
    var failure: (any Error)?

    mutating func next(isolation actor: isolated (any Actor)?) async throws -> Element? {
        if let element = try await base.next(isolation: actor) {
            return element
        }
        defer {
            failure = nil
        }
        if let failure {
            throw failure
        }
        return nil
    }

    mutating func next() async throws -> Element? {
        try await next(isolation: nil)
    }
}


struct DevicePartitionPlan<Device> {
    let unambiguousDevices: [Device]
    let ambiguousProductTypes: [String]

    init(_ devices: [Device], productType: KeyPath<Device, String>) {
        let partitions = Dictionary(grouping: devices, by: { $0[keyPath: productType] })
        let ambiguous = Set(partitions.compactMap { $0.value.count > 1 ? $0.key : nil })
        unambiguousDevices = devices.filter { !ambiguous.contains($0[keyPath: productType]) }
        ambiguousProductTypes = ambiguous.sorted()
    }
}

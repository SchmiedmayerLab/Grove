//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order
import Atomics
import Foundation

#if canImport(Darwin)
typealias AtomicPThread = ManagedAtomic<pthread_t?>
#elseif canImport(Glibc)
import Glibc

// Glibc (Linux): `pthread_t` is `UInt`
// Darwin (macOS/iOS): `pthread_t` is `UnsafeMutablePointer<_opaque_pthread_t>`
//
// Atomics support optionals of pointer types (Darwin), but not optionals of integer types (Glibc).
//
// To provide a similar representation on Glibc, we store UInts as non-optionals, and map `nil` <-> `0`.
struct AtomicPThread {
  private static let none: pthread_t = 0
  private let raw = ManagedAtomic<pthread_t>(none)

    init(_ initial: pthread_t? = nil) {
        raw.store(initial ?? Self.none, ordering: .relaxed)
    }

    func load(ordering _: AtomicLoadOrdering) -> pthread_t? {
        let loadedValue = raw.load(ordering: .relaxed)
        return loadedValue == Self.none ? nil : loadedValue
    }

    func store(_ value: pthread_t?, ordering _: AtomicStoreOrdering) {
        raw.store(value ?? Self.none, ordering: .relaxed)
  }
}
#else
#error("No Darwin and Glibc module found: can't provide a definition for AtomicPThread.")
#endif

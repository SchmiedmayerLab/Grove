//
// This source file is part of the HealthKitOnFHIR open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(macOS 13, *)
extension RangeReplaceableCollection {
    @inlinable
    mutating func removeElements(at indices: some Collection<Index>) {
        for idx in indices.sorted().reversed() {
            self.remove(at: idx)
        }
    }
}

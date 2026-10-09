//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// How an exporter builds its records' outputs on several child tasks while its caller receives them in input order.
package enum ConcurrentBuild {
    /// The most elements one child task builds: enough to keep a task's own cost small, few enough that faster cores
    /// take on more slices than slower ones.
    package static let maximumSliceSize = 8

    /// The child tasks an exporter builds on when its options set no limit: one per active core.
    package static var defaultWidth: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    /// `transform` of every element, in input order, on at most `width` child tasks that each transform one contiguous
    /// slice; on the calling task when there is one element or `width` is one.
    package static func map<Element: Sendable, Result: Sendable>(
        _ elements: ArraySlice<Element>,
        width: Int,
        _ transform: @escaping @Sendable (Element) -> Result
    ) async -> [Result] {
        let width = min(max(width, 1), elements.count)
        guard width > 1 else {
            return elements.map(transform)
        }
        let sliceSize = (elements.count + width - 1) / width
        return await withTaskGroup(of: (Int, [Result]).self) { group in
            var sliceCount = 0
            for start in stride(from: elements.startIndex, to: elements.endIndex, by: sliceSize) {
                let slice = elements[start..<min(start + sliceSize, elements.endIndex)]
                let index = sliceCount
                group.addTask {
                    (index, slice.map(transform))
                }
                sliceCount += 1
            }
            var slices = [[Result]](repeating: [], count: sliceCount)
            for await (index, results) in group {
                slices[index] = results
            }
            return slices.flatMap(\.self)
        }
    }

    /// Builds every element with `build` on at most `width` child tasks, a few contiguous elements per task, and hands
    /// each element and what was built for it to `hand` in input order, on the calling task, as soon as every element
    /// before it was handed over. At most `2 × width` slices are built ahead of the one `hand` waits for.
    ///
    /// - Throws: `CancellationError` once the task is cancelled, before the next slice is handed over, or what `hand`
    ///   throws; either stops the build.
    package nonisolated(nonsending) static func forEach<Element: Sendable, Built: Sendable>(
        _ elements: [Element],
        width: Int,
        build: @escaping @Sendable (Element) -> Built,
        hand: (Element, Built) throws -> Void
    ) async throws {
        let width = max(width, 1)
        guard width > 1, elements.count > 1 else {
            for element in elements {
                try Task.checkCancellation()
                try hand(element, build(element))
            }
            return
        }
        try Task.checkCancellation()
        // About four slices per child task, so faster cores build more of them than slower ones.
        let sliceSize = min(max(elements.count / (width * 4), 1), maximumSliceSize)
        let slices = stride(from: elements.startIndex, to: elements.endIndex, by: sliceSize).map {
            $0..<min($0 + sliceSize, elements.endIndex)
        }
        try await withThrowingTaskGroup(of: (Int, [Built]).self) { group in
            var started = 0
            var handed = 0
            var waiting: [Int: [Built]] = [:]
            while handed < slices.count {
                // Keep `width` slices building, and at most `2 × width` waiting to be handed over.
                while started < slices.count, started - handed - waiting.count < width, started - handed < 2 * width {
                    let index = started
                    let slice = elements[slices[index]]
                    group.addTask {
                        (index, slice.map(build))
                    }
                    started += 1
                }
                guard let (index, built) = try await group.next() else {
                    break
                }
                waiting[index] = built
                while let built = waiting.removeValue(forKey: handed) {
                    try Task.checkCancellation()
                    for (element, value) in zip(elements[slices[handed]], built) {
                        try hand(element, value)
                    }
                    handed += 1
                }
            }
        }
    }
}

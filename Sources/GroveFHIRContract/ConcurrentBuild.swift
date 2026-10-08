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
    /// The records built at once before their outputs are handed over, which bounds how many wait for the caller.
    package static let chunkSize = 256

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

    /// Builds `elements` a chunk at a time with `build` on at most `width` child tasks, and hands each element and what
    /// was built for it to `hand` in input order, on the calling task.
    ///
    /// - Throws: `CancellationError` before a chunk once the task is cancelled, or what `hand` throws; either stops the
    ///   remaining chunks.
    package nonisolated(nonsending) static func forEach<Element: Sendable, Built: Sendable>(
        _ elements: [Element],
        width: Int,
        build: @escaping @Sendable (Element) -> Built,
        hand: (Element, Built) throws -> Void
    ) async throws {
        for chunkStart in stride(from: elements.startIndex, to: elements.endIndex, by: chunkSize) {
            try Task.checkCancellation()
            let chunk = elements[chunkStart..<min(chunkStart + chunkSize, elements.endIndex)]
            let built = await map(chunk, width: width, build)
            for (element, value) in zip(chunk, built) {
                try hand(element, value)
            }
        }
    }
}

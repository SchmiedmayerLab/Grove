//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit {
    /// A utility iterator that can be used to efficiently work with ``SensorKit/FetchResult`` arrays.
    ///
    /// ``SensorKit/FetchResult``s returned from SensorKit can, depending on the specific sensor type, contain one or multiple individual samples that are all associated with the same ``SensorKit-class/FetchResult/sensorKitTimestamp``.
    /// This iterator enables efficient iteration over `(timestamp: Date, sample: Sample)` tuples for the elements from one or more ``SensorKit-class/FetchResult``s,
    /// without the need to perform unnecessary intermediate allocations.
    /// Since some sensors can result in very large amounts of data, this can have a significant impact.
    public struct FetchResultsIterator<Sample: AnyObject & Hashable, FetchResults: Collection<FetchResult<Sample>>>: Sequence, IteratorProtocol {
        public typealias Element = (timestamp: Date, sample: Sample)
        
        @usableFromInline var _state: State // swiftlint:disable:this identifier_name
        
        @inlinable
        public init(_ fetchResults: FetchResults) {
            _state = .init(fetchResults[...])
        }
        
        @inlinable
        public init(_ fetchResult: FetchResult<Sample>) where FetchResults == CollectionOfOne<FetchResult<Sample>> {
            self.init(CollectionOfOne(fetchResult))
        }
        
        @inlinable
        public mutating func next() -> Element? {
            switch _state {
            case .exhausted:
                return nil
            case .active(var current, let remaining):
                if let next = current.next() {
                    _state = .active(current: current, remaining: remaining)
                    return next
                } else {
                    // the FetchResult's iterator is empty, meaning that there are no more samples in the fetch result.
                    // we need to move on to the next batch.
                    // we do this by re-initializing the state with the remaining FetchResults,
                    // and then simply calling next() again.
                    _state = .init(remaining)
                    return next()
                }
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension SensorKit.FetchResultsIterator {
    @usableFromInline
    enum State {
        case active(
            current: LazyMapCollection<SensorKit.FetchResult<Sample>, Element>.Iterator,
            remaining: FetchResults.SubSequence
        )
        /// The iterator has reached its end. There are no more samples to yield.
        case exhausted
        
        @inlinable
        init(_ fetchResults: FetchResults.SubSequence) {
            if let idx = fetchResults.firstIndex(where: { !$0.isEmpty }) {
                self = .active(
                    current: Self.process(fetchResults[idx]),
                    remaining: fetchResults.dropFirst(fetchResults.distance(from: fetchResults.startIndex, to: fetchResults.index(after: idx)))
                )
            } else {
                self = .exhausted
            }
        }
        
        @inlinable
        static func process(
            _ fetchResult: SensorKit.FetchResult<Sample>
        ) -> LazyMapSequence<SensorKit.FetchResult<Sample>, Element>.Iterator {
            fetchResult.lazy
                .map { [date = fetchResult.sensorKitTimestamp] sample in (date, sample) }
                .makeIterator()
        }
    }
}

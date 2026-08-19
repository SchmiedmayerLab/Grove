# ``GroveFoundation``

<!--
#
# This source file is part of the Grove open-source project
#
# SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
#
# SPDX-License-Identifier: MIT
#       
-->

Grove Foundation provides a base layer of functionality useful in many applications, including fundamental types, algorithms, extensions, and data structures.

## Topics

### Data Structures
- <doc:Shared-Repository>
- ``OrderedArray``

### Calendar and Time Zone handling
- <doc:Calendar>

### Local Preferences (UserDefaults)
- <doc:LocalPreferences>

### Sequence and Collection utilities
- <doc:CollectionAlgorithms>

### Platform-Independent Logging
- <doc:Logger>

### Concurrency
- ``RWLock``
- ``RecursiveRWLock``
- ``withManagedTaskQueue(limit:_:)``
- ``AsyncSemaphore``
- ``ManagedAsynchronousAccess``
- ``runOrScheduleOnMainActor(_:)``
- ``CancelableTaskHandle``
- ``_Concurrency/DiscardingTaskGroup/addCancelableTask(_:)``

### Encoders and Decoders
- ``TopLevelEncoder``
- ``TopLevelDecoder``

### Generic Result Builders
- ``RangeReplaceableCollectionBuilder``
- ``ArrayBuilder``
- ``SetBuilder``
- ``Swift/Array/init(build:)``
- ``Swift/Set/init(build:)``

### Introspection
- ``AnyArray``
- ``AnyOptional``

### Data
- ``DataDescriptor``

### Compression
- ``CompressionAlgorithm``
- ``Zstd``
- ``Zlib``
- ``Swift/Collection/compressed(using:options:)``
- ``Swift/Collection/decompressed(using:)``

### Timeout
- ``TimeoutError``
- ``withTimeout(of:perform:)``

### Markdown
- ``MarkdownDocument``

### Objective-C Exception Handling
- ``catchingNSException(_:)``
- ``CaughtNSException``

### System Programming Interfaces
- <doc:SPI>

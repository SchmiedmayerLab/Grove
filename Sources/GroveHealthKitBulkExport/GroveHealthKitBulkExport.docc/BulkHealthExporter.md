# ``BulkHealthExporter``

<!--
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
-->

Export large amounts of historical Health data

## Overview

The ``BulkHealthExporter`` queries historical HealthKit samples in batches and passes them to a ``BatchProcessor``.

The Bulk Export API is built around Export Sessions (``BulkExportSession``), which keep track of pending and completed work across app launches.
Saved progress allows an export to continue after app termination, even for sample types with a large number of samples.

Export Sessions are created using ``BulkHealthExporter/session(withId:for:startDate:endDate:batchSize:using:)`` and consist of the following components:

- A stable identifier, used to persist the session's progress and restore it across app launches.
- A set of sample types to export over a configured time range.
- A ``BatchProcessor``, which allows the app to process each batch of fetched samples.

This structure supports different export operations, such as uploading samples to a server or writing FHIR-encoded files to disk (see the examples below).

Calling ``BulkHealthExporter/session(withId:for:startDate:endDate:batchSize:using:)`` either creates a new session, restores its saved progress, or returns the existing session with that identifier.
It is safe to retrieve the same session multiple times, including after completion; this does not restart processing.
Call ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)`` to begin processing and receive an `AsyncStream` of batch results.

The session retains its original export end date across launches.
An app can use `CollectSamples` for ongoing collection and the ``BulkHealthExporter`` for a one-time export of historical Health data.

- Important: Request HealthKit authorization before starting bulk export sessions; the exporter does not prompt for access.

It is possible to ``BulkExportSession/pause()`` an export session and resume it using ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)``.
See Pausing and Recovery below for checkpoint failures and restoration behavior.


### Example 1: Bulk-Upload of Historical Health Data to Firebase

This example implements a custom ``BatchProcessor``, which uploads the exported HealthKit samples received from the ``BulkHealthExporter`` into Firebase.
Both examples convert through one `HealthKitFHIRExporter`, built as [GroveHealthKitFHIR](../../GroveHealthKitFHIR/GroveHealthKitFHIR.docc/GroveHealthKitFHIR.md) describes.
Each batch is stored as the Bundles an `ExchangeBundlePacker` splices together from its records' validated bytes, each Bundle under its first record's version; the HealthKit UUID never names a stored object.
The processor keeps no retry state of its own: a record states the same source-record identity however often it is converted, so a batch processed again after a crash lets the receiver deduplicate.

```swift
struct FirebaseUploader: BatchProcessor {
    let participantID: String
    let exporter: HealthKitFHIRExporter

    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) async throws {
        let db = Firestore.firestore()
        let healthData = db.collection("participants").document(participantID).collection("healthData")
        let batch = db.batch()
        for graph in try await packedBundles(of: samples.map { $0 as HKSample }, exporter: exporter) {
            guard let version = try graph.records().first?.version else {
                continue
            }
            batch.setData(["graph": graph.json], forDocument: healthData.document(version.fullURL))
        }
        try await batch.commit()
    }
}

/// The batch's records, as the Bundles an upload sends: a record that takes a Bundle past a cap starts the next one.
func packedBundles(of samples: [HKSample], exporter: HealthKitFHIRExporter) async throws -> [ExchangeGraph] {
    var bundles: [ExchangeGraph] = []
    var packer = ExchangeBundlePacker(kind: .active)
    try await exporter.export(samples) { export in
        guard let record = export.record else {
            return
        }
        if try packer.add(record) == .deferred {
            bundles.append(try packer.bundle(packedAt: .now))
            packer = ExchangeBundlePacker(kind: .active)
            _ = try packer.add(record)
        }
    }
    if packer.recordCount > 0 {
        bundles.append(try packer.bundle(packedAt: .now))
    }
    return bundles
}
```

We can then use the batch processor when creating a Bulk Export Session:
```swift
extension BulkExportSessionIdentifier {
    static let backgroundExport = Self("my-bulk-export-session")
}

// create the session (or obtain a previously-created session)
let session = try await bulkExporter.session(
    withId: .backgroundExport,
    for: [SampleType.activeEnergyBurned, SampleType.heartRate, SampleType.stepCount],
    startDate: .oldestSample,
    using: FirebaseUploader(participantID: participantID, exporter: exporter)
)

// start the session; the processor's output is `Void`, so its stream goes unread
_ = try session.start()
```

This Bulk Export Session will, in the background, go through all historical Health data for the Active Energy, Heart Rate, and Step Count quantity types, fetch the data from HealthKit, and pass it to the Batch Processor, which will then upload it to Firebase. Firebase is only the destination chosen by this example; `GroveHealthKitFHIR` neither depends on Firebase nor reads from it.

In this example the `FirebaseUploader` has no output, so the example discards the `AsyncStream` that ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)`` returns.



### Example 2: Bulk-Export of FHIR-Encoded Historical Health Data to Disk

This example combines the [`GroveHealthKitFHIR`](../../GroveHealthKitFHIR/GroveHealthKitFHIR.docc/GroveHealthKitFHIR.md) library with the Bulk Exporter, to store each batch into a FHIR-encoded JSON file:
```swift
extension BulkExportSessionIdentifier {
    static let backgroundFHIRExport = Self("my-fhir-bulk-export-session")
}

struct FHIREncodedJSONExporter: BatchProcessor {
    let exporter: HealthKitFHIRExporter

    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) async throws -> URL {
        // `packedBundles` is the function of the example above.
        let bundles = try await packedBundles(of: samples.map { $0 as HKSample }, exporter: exporter).map(\.json)
        // A JSON array of the validated Bundle bytes, spliced verbatim rather than re-encoded.
        let file = Data("[".utf8) + bundles.joined(separator: Data(",".utf8)) + Data("]".utf8)
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .json)
        try file.write(to: url)
        return url
    }
}

// create the session
let session = try await bulkExporter.session(
    withId: .backgroundFHIRExport,
    for: [SampleType.activeEnergyBurned, SampleType.heartRate, SampleType.stepCount],
    startDate: .oldestSample,
    using: FHIREncodedJSONExporter(exporter: exporter)
)

// start the session
let results = try session.start()

// await the results
Task {
    for await url in results {
        // process the JSON file at `url` in some way
    }
}
```

Since the `FHIREncodedJSONExporter` returns a `URL`, the ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)`` function's return type will be an `AsyncStream<URL>`, which gives us access to the individual batch processing results (in this case the urls of the exported JSON files).


### Pausing and Recovery

A session remains `.running` until its workers finish and the final checkpoint write has been attempted.
`.completed` means every batch succeeded and the checkpoint was stored; it does not confirm upload delivery.
When a session pauses, inspect the associated ``BulkExportPauseReason``:

| Reason | Recovery |
|---|---|
| `.notStarted` | Start the newly created or restored session. |
| `.requested` | Resume when the caller requests it. |
| `.failedBatches` | Inspect `failedBatches`, address the batch errors, and start with `retryFailedBatches: true`. |
| `.failure(.checkpointWriteFailed(error))` | Retain the session and generated files. Address `error.category` before retrying. |

``CheckpointWriteFailure`` provides a recovery category and the error domain, code and message.
For `.insufficientSpace`, free storage; for `.temporarilyUnavailable`, wait for storage to become available.
For `.accessDenied`, check permissions and protected-data availability; the error alone does not identify the cause.
For `.invalidDestination`, correct the storage location; for `.unknown`, inspect the diagnostics before deciding whether to retry.

After resolving the cause, use the existing session:

```swift
let results = try session.start(retryFailedBatches: true)
for await output in results {
    // Process or queue each output for upload.
}
// Inspect session.state for completion or another pause reason.
```

Outputs enter the stream only after their batch completion is checkpointed, followed by ``BatchProcessor/didPersist(_:)``.
If a checkpoint write fails, the session stops starting new batches, drains work already running, and pauses with the checkpoint error.
Successful processing stays completed in memory; its unpublished output is retained instead of processing the batch again.
On the next `start`, the session first persists its current progress and then publishes retained outputs before processing remaining batches.
Retrying persistence does not require `retryFailedBatches: true`; that flag also retries batches whose processing failed.
The first checkpoint error remains the pause reason even if a later write succeeds during draining.
Outputs whose own checkpoint succeeded can still be delivered during that drain; failed publications wait for the next `start`.

Saved checkpoints restore completed batches and remaining work across launches, but do not contain processor outputs.
If the app terminates before progress is saved, restoration may repeat those batches.
If progress was saved before an output was yielded or consumed, restoration skips that completed batch and cannot replay the output.
The checkpoint records processing progress; it is separate from generated files, stream consumption, and uploads.
Keep durable export or upload work in the batch processor, and use `didPersist` only for optional cleanup of retry state.
A processor that stores raw samples deduplicates them by participant ID and sample UUID.
One that exports exchange records, as both examples do, needs no UUID: a batch exported again states the same source-record identities, on which the receiver deduplicates, and the same record versions when it repeats the export instant.

A checkpoint failure takes precedence over a requested pause or batch failures; inspect `failedBatches` for any batch errors.
Retry after a user action or storage availability change, rather than in a loop.
Delete restoration information only for an intentional restart: termination discards any retained unpublished outputs.

### Performance Considerations

To reduce memory use when exporting large amounts of HealthKit data, the exporter fetches each sample type in time-based batches rather than loading its entire history at once.
With ``ExportSessionBatchSize/automatic``, high-volume types such as heart rate and step count use monthly batches; other types use six-month batches.
Callers can choose a different calendar-based batch size through ``ExportSessionBatchSize``.

Use `concurrencyLevel: .limit(n)` to cap concurrent batches or `.disabled` for serial processing; `.automatic` currently uses unlimited concurrency.
After a checkpoint failure, outputs from already-running batches may remain in memory until recovery or termination.
Choose a finite concurrency limit when outputs are large; unlimited concurrency also permits unlimited retained outputs.
Multiple sessions can also run concurrently.
Keep the number of simultaneous sessions low and choose batch limits based on the processor's memory and I/O needs.


## Topics

### Creating a Bulk Exporter
- ``BulkHealthExporter/init()``

### Creating and Managing Export Sessions
- ``BulkHealthExporter/sessions``
- ``BulkHealthExporter/session(withId:for:startDate:endDate:batchSize:using:)``
- ``BulkHealthExporter/deleteSessionRestorationInfo(for:)``

### Export Session Types
- ``BulkExportSession``
- ``BatchProcessor``
- ``BulkExportSessionState``
- ``BulkExportPauseReason``
- ``BulkExportSessionFailure``
- ``CheckpointWriteFailure``
- ``BulkHealthExporter/SessionError``

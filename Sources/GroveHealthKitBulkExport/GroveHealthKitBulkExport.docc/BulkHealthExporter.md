# ``BulkHealthExporter``

<!--
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
-->

Export large amounts of historical Health data

## Overview

The ``BulkHealthExporter`` queries historical HealthKit samples in batches and passes them to a ``BatchProcessor``.
Each ``BulkExportSession`` has a stable identifier, configured sample types and a processor.
Session progress is checkpointed for restoration across app launches.

Call ``BulkHealthExporter/session(withId:for:startDate:endDate:batchSize:using:)`` to create a session, restore its saved progress, or retrieve the existing session with that identifier.
Then call ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)`` to begin processing and receive an `AsyncStream` of batch results.
The session uses its original export end date; use `CollectSamples` for ongoing collection.

Request HealthKit authorization before starting; the exporter does not prompt for access.
Use ``BulkExportSession/pause()`` to pause and `start()` to resume.


### Example 1: Bulk-Upload of Historical Health Data to Firebase

This example implements a custom ``BatchProcessor``, which uploads the exported HealthKit samples received from the ``BulkHealthExporter`` into Firebase. 
In this case, we implicitly define the Batch Processor's `Output` type as `Void`, since we're just interested in the uploading, and don't want to perform any additional on-device operations using the results of the individual batches. 

```swift
struct FirebaseUploader: BatchProcessor {
    let participantID: String

    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) async throws {
        let db = Firestore.firestore()
        let healthData = db.collection("participants").document(participantID).collection("healthData")
        let batch = db.batch()
        for sample in samples {
            let document = healthData.document(sample.uuid.uuidString)
            try batch.setData(from: sample.resource(), for: document)
        }
        try await batch.commit()
    }
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
    for: [SampleType.activeEnergy, SampleType.heartRate, SampleType.stepCount],
    using: FirebaseUploader(participantID: participantID)
)

// start the session
try session.start()
```

This Bulk Export Session will, in the background, go through all historical Health data for the Active Energy, Heart Rate, and Step Count quantity types, fetch the data from HealthKit, and pass it to the Batch Processor, which will then upload it to Firebase.

In this example, since the `FirebaseUploader`'s `Output` type is `Void`, we simply can call ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)`` and don't need to do anything beyond that.



### Example 2: Bulk-Export of FHIR-Encoded Historical Health Data to Disk

This example combines the [`GroveHealthKitFHIR`](../../GroveHealthKitFHIR/GroveHealthKitFHIR.docc/GroveHealthKitFHIR.md) library with the Bulk Exporter, to store each batch into a FHIR-encoded JSON file:
```swift
extension BulkExportSessionIdentifier {
    static let backgroundFHIRExport = Self("my-fhir-bulk-export-session")
}

struct FHIREncodedJSONExporter: BatchProcessor {
    func process<Sample>(_ samples: consuming [Sample], of sampleType: SampleType<Sample>) throws -> URL {
        let resources = try samples.mapIntoResourceProxies() // using GroveHealthKitFHIR
        let encoded = try JSONEncoder().encode(resources)
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, conformingTo: .json)
        try encoded.write(to: url)
        return url
    }
}

// create the session
let session = try await bulkExporter.session(
    withId: .backgroundFHIRExport,
    for: [SampleType.activeEnergy, SampleType.heartRate, SampleType.stepCount],
    using: FHIREncodedJSONExporter()
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

Since the `FHIREncodedExporter` returns a `URL` (rather than `Void`, as with the `FirebaseUploader`), the ``BulkExportSession/start(retryFailedBatches:concurrencyLevel:)`` function's return type will be an `AsyncStream<URL>` which gives us access to the individual batch processing results (in this case the urls of the exported JSON files).


### Pausing and Recovery

A session remains `.running` until its workers finish and the final checkpoint write has been attempted.
`.completed` means every batch succeeded and the checkpoint was stored; it does not confirm upload delivery.
When a session pauses, inspect the associated ``BulkExportPauseReason``:

| Reason | Recovery |
|---|---|
| `.notStarted` | Start the newly created or restored session. |
| `.requested` | Resume when the caller requests it. |
| `.failedBatches` | Inspect `failedBatches`, address the batch errors, and start with `retryFailedBatches: true`. |
| `.failure(.checkpointWriteFailed(error))` | Retain the session and emitted files. Address `error.category` before retrying. |

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

Saved checkpoints restore completed batches and remaining work across launches.
If a checkpoint write fails, the live session retains its latest progress, so a retry need not repeat completed batches.
If the app terminates before that progress is saved, restoration may repeat those batches.
The checkpoint records processing progress; it is separate from generated files and upload receipts.
Deduplicate HealthKit samples by participant ID and sample UUID.

A checkpoint failure takes precedence over a requested pause or batch failures; inspect `failedBatches` for any batch errors.
Retry after a user action or storage availability change, rather than in a loop.
Delete restoration information only for an intentional restart.

### Performance Considerations

Queries are batched by time range to limit the number of samples loaded at once.
Use `concurrencyLevel: .limit(n)` to cap concurrent batches or `.disabled` for serial processing; `.automatic` currently uses unlimited concurrency.
Multiple sessions can also run concurrently, so choose limits based on the processor's memory and I/O needs.


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

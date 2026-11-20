# ``GroveSensorKit``

<!--

This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Interact with SensorKit in your Grove application

## Overview
The Grove SensorKit module enables apps to integrate with Apple's [SensorKit](https://developer.apple.com/documentation/sensorkit) system, such as requesting authorization, setting up background data collection, and fetching collected samples.

### Setup
You need to add the Grove SensorKit Swift package to
 [your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) or
 [Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Grove, follow the
 [Grove setup article](../../Grove/Grove.docc/Initial-Setup.md) and set up the core Grove infrastructure.


### SensorKit Entitlements

In order to use SensorKit in your app, you need to list each sensor you want to access in your app's entitlements file.

Create an entry for the `com.apple.developer.sensorkit.reader.allow` key, of type array, and add each sensor's key to that array.

| Sensor                      | Entitlement            |
| :-------------------------- | :--------------------- |
| ``Sensor/accelerometer``    | `motion-accelerometer` |
| ``Sensor/ambientLight``     | `ambient-light-sensor` |
| ``Sensor/ambientPressure``  | `ambient-pressure`     |
| ``Sensor/deviceUsage``      | `device-usage`         |
| ``Sensor/ecg``              | `ECG`                  |
| ``Sensor/heartRate``        | `heart-rate`           |
| ``Sensor/onWrist``          | `on-wrist`             |
| ``Sensor/pedometer``        | `pedometer`            |
| ``Sensor/ppg``              | `PPG`                  |
| ``Sensor/visits``           | `visits`               |
| ``Sensor/wristTemperature`` | `wrist-temperature`    |


### Example
You use the ``Sensor`` type to interact with individual SensorKit sensors.

> Note: SensorKit enforces a quarantine period for each sensor's data; apps can only access data once a certain, sensor-specific time period has passed.
  GroveSensorKit is aware of each sensor's ``Sensor/dataQuarantineDuration`` and will automatically adjust your fetch requests to not overlap with the quarantine time periods.


#### SensorKit Sample Safe Representations
Since most sensors' returned samples aren't thread-safe, GroveSensorKit provides so-called "safe representations" for most sensors, which are small Swift structs that act as `Sendable` representations of the data returned by a ``Sensor``.
When you fetch data from a sensor (e.g., using ``Sensor/fetch(from:timeRange:)`` or ``SensorKit-class/fetchAnchored(_:acquisitionNamespace:batchSize:initialStartDate:ecgProcessingLimits:)``), GroveSensorKit automatically transforms the raw SensorKit samples into their respective safe representations.
For some sensors this step also performs additional pre-processing; for example, when fetching ECG data, SensorKit returns a bunch of individual [`SRElectrocardiogramSample`](https://developer.apple.com/documentation/sensorkit/srelectrocardiogramsample) objects each of which represents just a small part of the total ECG.
Fetching ECG data via GroveSensorKit implicitly processes the raw `SRElectrocardiogramSample`s into ``SensorKitECGSession``s, each of which represents a logical ECG session.
The safe representation retains the source session identifier, every observed provider session state,
the per-point flags, and the waveform values. This lets downstream persistence preserve the complete
native evidence instead of reconstructing it from the clinical waveform alone.


#### Fetching Data: Standalone One-Off Queries
Use ``Sensor/fetch(from:timeRange:)`` and ``Sensor/fetch(from:mostRecentAvailable:)`` to perform one-off queries:

```swift
import GroveSensorKit

let sensor = Sensor.heartRate
let devices = try await sensor.fetchDevices()
for device in devices {
    let results = try await sensor.fetch(from: device, mostRecentAvailable: .days(2))
    for sample in results {
        print(sample.timestamp, sample.value, sample.confidence)
    }
}
```


#### Fetching Data: Anchored Queries
You can implement continuous SensorKit data fetching using the Anchored Fetching API (e.g., ``SensorKit-class/fetchAnchored(_:acquisitionNamespace:batchSize:initialStartDate:ecgProcessingLimits:)``).
The ``SensorKit-class/fetchAnchored(_:acquisitionNamespace:batchSize:initialStartDate:ecgProcessingLimits:)`` function returns an `AsyncSequence` which fetches batches of SensorKit data on-demand (as the sequence is being iterated), and keeps track of the most recent already-fetched timestamp.

```swift
import GroveSensorKit

for try await batch in try await sensorKit.fetchAnchored(.ecg) {
    // do smth with a batch of `
}
```

Pass an `acquisitionNamespace` to keep the cursors of one source apart from every other source's; ``SensorKit-class/resetQueryAnchors(for:acquisitionNamespace:)`` and ``SensorKit-class/discardPendingBatches(for:acquisitionNamespace:)`` act on the cursors of the namespace you name, and ``SensorKit-class/removeQueryAnchors(acquisitionNamespace:)`` removes a namespace's cursors once its source has ended. An `initialStartDate` sets where an empty cursor starts. Each batch's `info.replayToken` lets ``SensorKit-class/replay(_:from:ecgProcessingLimits:)`` fetch the same batch again, without touching the live cursor, until the batch is acknowledged.


#### Batch Boundaries and Replay
A sample-count batch ends at a boundary: the largest SensorKit timestamp received when the batch's last sample was added, not counting ECG fetch results without session data (see below). A batch is delivered only after a fetch result with a later timestamp, or the end of the native fetch, so every fetch result with the boundary's timestamp belongs to the batch. The batch size, the ECG limits and the end of the native fetch decide when a batch is delivered; for a given sample count, its samples and its boundary depend only on the fetch results up to the first one after the boundary's timestamp, or the end of the fetch. After delivering a batch, the fetch continues as a fetch from the boundary does: it starts over and processes the fetch results after the boundary again.

A fetch that starts at the same cursor with the batch's sample count as its batch size delivers the same batch again, also when SensorKit returns newer data by then, as long as SensorKit returns the same fetch results in the same order. A restart before the acknowledgement and ``SensorKit-class/replay(_:from:ecgProcessingLimits:)`` both fetch a batch this way. Otherwise the restarted fetch fails with ``SensorKit-class/QueryAnchorAcknowledgementError/pendingBatchMismatch``, which ``SensorKit-class/discardPendingBatches(for:acquisitionNamespace:)`` recovers from, and the replay fails with ``SensorKit-class/BatchReplayError/batchUnavailable``.

The cursor is a SensorKit timestamp. Fetch results are expected in ascending timestamp order, and a fetch is expected to return only the results after its start. A fetch result that adds no sample after the batch's last one stays after the boundary, so the next fetch reads it again. A fetch that delivers no batch leaves the cursor where it is.


#### ECG Sessions
With ``SensorKitECGProcessingLimits`` and a sample-count batch size, ECG sessions whose samples arrive in several fetch results are assembled into complete sessions. A sample is then one session, so the batch size counts sessions.

- A session that has all its states but can't be assembled is skipped and logged by count. So is a fragment of a session that was delivered or skipped earlier, as long as the fetch still knows the session: it forgets the sessions before a batch's boundary when it delivers the batch, and the skipped sessions when it reaches the session limit without a sample to deliver. A fragment of a session the fetch isn't assembling is skipped the same way unless its fetch result carries the session's begin state, since it can't become a session; it doesn't end the unfinished sessions either.
- An unfinished session ends when a fetch result carries data of another session and none of its own. It is delivered without its end state, or skipped without its begin state or voltage samples, and joins the batch at the boundary before that fetch result. A fetch result that carries no data of a session the fetch is assembling, because its groups are all fragments the fetch skips or it has none, doesn't move that boundary, and its peripheral isn't named for the batch. The sessions of one device are expected not to overlap in time; when they do, the interrupted session is delivered once, without the data that arrives after the other session started. This assumes that SensorKit doesn't send a session's begin state again: a repeated begin state after a batch's boundary starts the session anew.
- A batch can end only where a fetch from its boundary reads again everything the batch leaves out: every unfinished session must have started after the boundary. A fetch result that completes one session and starts another, and a fetch result with the timestamp of the boundary or an earlier one, leave no boundary between the sessions, so both sessions belong to the same batch.
- A fetch that ends in unfinished sessions holds them: the batch ends at the last boundary before them, and the next fetch reads them whole. Without such a boundary the fetch delivers no batch and the cursor stays.
- Sessions are held only while the latest fetch result of the unfinished sessions is at most one hour older than the sensor's quarantine cutoff when the fetch starts. Otherwise they are delivered without their end state or skipped, as if another session had followed them. If SensorKit returns more data of such a session afterwards, a restart or replay of its batch fails as described above.
- A fetch result that doesn't fit the limits together with the sessions retained so far ends the batch at its last boundary, and the fetch goes on with the next batch. The limits count the batch's delivered sessions and the unfinished ones. The fetch fails with ``SensorKitECGSession/ProcessingError/assemblyCapacityExceeded`` when a fetch result doesn't fit the limits together with the sessions that no batch can end before, such as a single session larger than the limits; the cursor stays, so a retry with larger limits can assemble it.

A time-range fetch keeps a session without its end state and skips a session without its begin state or voltage samples, or with inconsistent facts.

### Performance Considerations
The amount of samples collected varies significantly across the different sensors.
While some of them collect only a small number of samples, some others (e.g., ``Sensor/ambientPressure``) will collect large amounts of data; fetching too many samples at once, or using inefficient Array-based operations will incur performance penalties and might cause your app to crash if it runs out of memory.

Make sure in your app to use lazy sequence/collection operations when possible when working with SensorKit data (see e.g. the example above).

Additionally, GroveSensorKit offers the ``SensorKit/FetchResultsIterator`` to efficiently process individual samples alongside their SensorKit timestamps, without unnecessary intermediate allocations.


### Threading Considerations
When performing multiple queries on a single ``Sensor`` at the same time, ensure that the individual fetches have non-overlapping time periods.



## Topics

### The SensorKit Module
- ``SensorKit-class``

### Permission Handling
- ``SensorKit/authorizationStatus(for:)``
- ``SensorKit/requestAccess(to:)``

### Working with Sensors
- ``Sensor``
- ``AnySensor``

### Sensor Data
- ``SensorKitSampleProtocol``
- ``SensorKitECGSession``
- ``SensorKitOnWristEventSample``

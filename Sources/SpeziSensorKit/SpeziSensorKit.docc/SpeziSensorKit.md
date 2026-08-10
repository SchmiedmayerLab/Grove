# ``SpeziSensorKit``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Interact with SensorKit in your Spezi application

## Overview
The Spezi SensorKit module enables apps to integrate with Apple's [SensorKit](https://developer.apple.com/documentation/sensorkit) system, such as requesting authorization, setting up background data collection, and fetching collected samples.

### Setup
You need to add the Spezi SensorKit Swift package to
 [your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) or
 [Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package).

> Important: If your application is not yet configured to use Spezi, follow the
 [Spezi setup article](../../Spezi/Spezi.docc/Initial%20Setup.md) and set up the core Spezi infrastructure.


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
  SpeziSensorKit is aware of each sensor's ``Sensor/dataQuarantineDuration`` and will automatically adjust your fetch requests to not overlap with the quarantine time periods.


#### SensorKit Sample Safe Representations
Since most sensors' returned samples aren't thread-safe, SpeziSensorKit provides so-called "safe representations" for most sensors, which are small Swift structs that act as `Sendable` representations of the data returned by a ``Sensor``.
When you fetch data from a sensor (e.g., using ``Sensor/fetch(from:timeRange:)`` or ``SensorKit-class/fetchAnchored(_:batchSize:)``), SpeziSensorKit automatically transforms the raw SensorKit samples into their respective safe representations.
For some sensors this step also performs additional pre-processing; for example, when fetching ECG data, SensorKit returns a bunch of individual [`SRElectrocardiogramSample`](https://developer.apple.com/documentation/sensorkit/srelectrocardiogramsample) objects each of which represents just a small part of the total ECG.
Fetching ECG data via SpeziSensorKit implicitly processes the raw `SRElectrocardiogramSample`s into ``SensorKitECGSession``s, each of which represents a logical ECG session.


#### Fetching Data: Standalone One-Off Queries
Use ``Sensor/fetch(from:timeRange:)`` and ``Sensor/fetch(from:mostRecentAvailable:)`` to perform one-off queries:

```swift
import SpeziSensorKit

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
You can implement continuous SensorKit data fetching using the Anchored Fetching API (e.g., ``SensorKit-class/fetchAnchored(_:batchSize:)``).
The ``SensorKit-class/fetchAnchored(_:batchSize:)`` function returns an `AsyncSequence` which fetches batches of SensorKit data on-demand (as the sequence is being iterated), and keeps track of the most recent already-fetched timestamp.

```swift
import SpeziSensorKit

for try await batch in try await sensorKit.fetchAnchored(.ecg) {
    // do smth with a batch of `
}
```

### Performance Considerations
The amount of samples collected varies significantly across the different sensors.
While some of them collect only a small number of samples, some others (e.g., ``Sensor/ambientPressure``) will collect large amounts of data; fetching too many samples at once, or using inefficient Array-based operations will incur performance penalties and might cause your app to crash if it runs out of memory.

Make sure in your app to use lazy sequence/collection operations when possible when working with SensorKit data (see e.g. the example above).

Additionally, SpeziSensorKit offers the ``SensorKit/FetchResultsIterator`` to efficiently process individual samples alongside their SensorKit timestamps, without unnecessary intermediate allocations.


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

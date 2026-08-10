<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# Spezi SensorKit


Interact with SensorKit in your Spezi app.

## Overview
The Spezi SensorKit module enables apps to integrate with Apple's [SensorKit](https://developer.apple.com/documentation/sensorkit) system, such as requesting authorization, setting up background data collection, and fetching collected samples.


### Example

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


For more information, please refer to the [API documentation](SpeziSensorKit.docc/SpeziSensorKit.md).

## The Spezi Template Application

The Spezi Template Application provides a great starting point and example using the `SpeziSensorKit` module.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing-Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

# SpeziBluetooth


Connect and communicate with Bluetooth devices using modern programming paradigms.


## Overview

The Spezi Bluetooth module provides a convenient way to handle state management with a Bluetooth device,
retrieve data from different services and characteristics,
and write data to a combination of services and characteristics.

This package uses Apples [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) framework under the hood.

> [!NOTE]
> You will need a basic understanding of the Bluetooth Terminology and the underlying software model to
  understand the structure and API of the Spezi Bluetooth module. You can find a good overview in the
  [Wikipedia Bluetooth Low Energy (LE) Software Model section](https://en.wikipedia.org/wiki/Bluetooth_Low_Energy#Software_model)
  or the [Developer’s Guide to Bluetooth Technology](https://www.bluetooth.com/blog/a-developers-guide-to-bluetooth/).


## Setup


### Add Spezi Bluetooth as a Dependency

Add the Spezi monorepo package to your app and select the `SpeziBluetooth` product.

In Xcode, select **File > Add Package Dependencies...**, enter:

```text
https://github.com/SchmiedmayerLab/Spezi.git
```

Choose **Up to Next Minor Version** and enter the latest tagged `0.x` release, for example `0.1.0`.

If you manage dependencies in a `Package.swift`, add the package dependency:

```swift
.package(url: "https://github.com/SchmiedmayerLab/Spezi.git", .upToNextMinor(from: "0.1.0"))
```

Then add the product dependency to the target that needs it:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "SpeziBluetooth", package: "Spezi")
    ]
)
```

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](../Spezi/Spezi.docc/Initial%20Setup.md) to set up the core Spezi infrastructure.

### Register the Module

The `Bluetooth` module needs to be registered in a Spezi-based application using the
`configuration` in a
`SpeziAppDelegate`:
```swift
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Bluetooth {
                // discover devices ...
            }
        }
    }
}
```

> [!NOTE]
> You can learn more about a [`Module`](../Spezi/Spezi.docc/Module/Module.md) in the Spezi documentation.


## Example

### Create your Bluetooth device

The `Bluetooth`
module allows to declarative define your Bluetooth device using a `BluetoothDevice` implementation and property wrappers
like `Service` and `Characteristic`.

The below code examples demonstrate how you can implement your own Bluetooth device.

First of all we define our Bluetooth service by implementing a `BluetoothService`.
We use the `Characteristic` property wrapper to declare its characteristics.
Note that the value types needs to be optional and conform to
`ByteEncodable`,
`ByteDecodable` or
`ByteCodable` respectively.

```swift
struct DeviceInformationService: BluetoothService {
    static let id: BTUUID = "180A"

    @Characteristic(id: "2A29")
    var manufacturer: String?
    @Characteristic(id: "2A26")
    var firmwareRevision: String?
}
```

We can use this Bluetooth service now in the `MyDevice` implementation as follows.

> [!TIP]
> We use the `DeviceState` and `DeviceAction` property wrappers to get access to the device state and its actions. Those two
  property wrappers can also be used within a `BluetoothService` type.

```swift
class MyDevice: BluetoothDevice {
    @DeviceState(\.id)
    var id: UUID
    @DeviceState(\.name)
    var name: String?
    @DeviceState(\.state)
    var state: PeripheralState

    @Service var deviceInformation = DeviceInformationService()

    @DeviceAction(\.connect)
    var connect
    @DeviceAction(\.disconnect)
    var disconnect

    required init() {}
}
```

### Configure the Bluetooth Module

We use the above `BluetoothDevice` implementation to configure the `Bluetooth` module within the
SpeziAppDelegate.

```swift
import Spezi

class ExampleDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Bluetooth {
                // Define which devices type to discover by what criteria .
                // In this case we search for some custom FFF0 service that is advertised.
                Discover(MyDevice.self, by: .advertisedService("FFF0"))
            }
        }
    }
}
```

### Using the Bluetooth Module

Once you have the `Bluetooth` module configured within your Spezi app, you can access the module within your
[`Environment`](https://developer.apple.com/documentation/swiftui/environment).

You can use the `scanNearbyDevices(enabled:with:minimumRSSI:advertisementStaleInterval:autoConnect:)`
and `autoConnect(enabled:with:minimumRSSI:advertisementStaleInterval:)`
modifiers to scan for nearby devices and/or auto connect to the first available device. Otherwise, you can also manually start and stop scanning for nearby devices
using `scanNearbyDevices(minimumRSSI:advertisementStaleInterval:autoConnect:)` and `stopScanning()`.

To retrieve the list of nearby devices you may use `nearbyDevices(for:)`.

> [!TIP]
> To easily access the first connected device, you can just query the SwiftUI Environment for your `BluetoothDevice` type.
  Make sure to declare the property as optional using the respective [`Environment(_:)`](<https://developer.apple.com/documentation/swiftui/environment/init(_:)-8slkf>)
  initializer.

The below code example demonstrates all these steps of retrieving the `Bluetooth` module from the environment, listing all nearby devices,
auto connecting to the first one and displaying some basic information of the currently connected device.

```swift
import SpeziBluetooth
import SwiftUI

struct MyView: View {
    @Environment(Bluetooth.self)
    var bluetooth
    @Environment(MyDevice.self)
    var myDevice: MyDevice?

    var body: some View {
        List {
            if let myDevice {
                Section {
                    Text("Device")
                    Spacer()
                    Text("\(myDevice.state.description)")
                }
            }

            Section {
                ForEach(bluetooth.nearbyDevices(for: MyDevice.self), id: \.id) { device in
                    Text("\(device.name ?? "unknown")")
                }
            } header: {
                HStack {
                    Text("Devices")
                        .padding(.trailing, 10)
                    if bluetooth.isScanning {
                        ProgressView()
                    }
                }
            }
        }
            .scanNearbyDevices(with: bluetooth, autoConnect: true)
    }
}
```

> [!TIP]
> Use `ConnectedDevices` to retrieve the full list of connected devices from the SwiftUI environment.

#### Retrieving Devices

The previous section explained how to discover nearby devices and retrieve the currently connected one from the environment.
This is great ad-hoc connection establishment with devices currently nearby.
However, this might not be the most efficient approach, if you want to connect to a specific, previously paired device.
In these situations you can use the `retrieveDevice(for:as:)` method to retrieve a known device.

Below is a short code example illustrating this method.

```swift
let id: UUID = ... // a Bluetooth peripheral identifier (e.g., previously retrieved when pairing the device)

let device = bluetooth.retrieveDevice(for: id, as: MyDevice.self)

await device.connect() // assume declaration of @DeviceAction(\.connect)

// Connect doesn't time out. Connection with the device will be established as soon as the device is in reach.
```

### Integration with Spezi Modules

A Spezi `Module` is a great way of structuring your application into
different subsystems and provides extensive capabilities to model relationship and dependence between modules.
Every `BluetoothDevice` is a `Module`.
Therefore, you can easily access your SpeziBluetooth device from within any Spezi `Module` using the standard
[`Module` dependency infrastructure](../Spezi/Spezi.docc/Module/Module%20Dependency.md). At the same time,
every `BluetoothDevice` can benefit from the same capabilities as every other Spezi `Module`.

Below is a short code example demonstrating how a `BluetoothDevice` uses the `@Dependency` property to interact with a Spezi Module that is
configured within the Spezi application.

```swift
class Measurements: Module, EnvironmentAccessible, DefaultInitializable {
    required init() {}

    func recordNewMeasurement(_ measurement: WeightMeasurement) {
        // ... process measurement
    }
}

class MyDevice: BluetoothDevice {
    @Service var weightScale = WeightScaleService()

    // declare dependency to a configured Spezi Module
    @Dependency var measurements: Measurements

    required init() {}

    func configure() {
        weightScale.$weightMeasurement.onChange { [weak self] value in
            self?.handleNewMeasurement(value)
        }
    }

    private func handleNewMeasurement(_ measurement: WeightMeasurement) {
        measurements.recordNewMeasurement(measurement)
    }
}
```

For more information, please refer to the [API documentation](SpeziBluetooth.docc/SpeziBluetooth.md).


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guide](../Spezi/Spezi.docc/Contributing%20Guide.md) and the [Contributor Covenant Code of Conduct](https://github.com/SchmiedmayerLab/.github/blob/main/CODE_OF_CONDUCT.md) first.

## License

This target is licensed under the MIT License. The local [LICENSES](LICENSES) directory records license information imported from the original upstream repository. See the monorepo [LICENSES](../../LICENSES) directory for license information covering current changes in this repository.


## Contributors

The local [CONTRIBUTORS.md](CONTRIBUTORS.md) file records contributors from the original upstream repository. See the monorepo [CONTRIBUTORS.md](../../CONTRIBUTORS.md) file for contributors to current changes in this repository.

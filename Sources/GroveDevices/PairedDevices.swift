//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(AccessorySetupKit) && !os(macOS)
public import AccessorySetupKit
#endif
public import Foundation
public import Grove
public import GroveBluetooth
import GroveBluetoothServices
@_spi(TestingSupport)
import GroveFoundation
// periphery:ignore - referenced only from physical-device builds (the scan indexes a simulator destination)
import GroveLegacyIdentifiers
import GroveViews
public import Observation
import OrderedCollections
import OSLog
import SwiftData
import SwiftUI


/// Persistently pair with Bluetooth devices and automatically manage connections.
///
/// Use the `PairedDevices` module to discover and pair ``PairableDevice``s and automatically manage connection establishment
/// of connected devices.
/// - Note: Implement your device as a [`BluetoothDevice`](../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md)
///     using [GroveBluetooth](../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md).
///
/// ## AccessorySetupKit
///
///  `PairedDevices` natively supports the `AccessorySetupKit`. Use ``showAccessoryDiscovery()`` to present the accessory picker.
///
///  - Note: If migrating from existing PairedDevices to AccessorySetupKit make sure to check ``needsAccessorySetupKitMigration`` and call ``showAccessoryMigration()`` to have
///     existing accessories keep working. If not called explicitly, devices will be paired once the next accessory is setup up using ``showAccessoryDiscovery()``.
///
/// ## Legacy CoreBluetooth-based Discovery
///
/// To support `PairedDevices`, you need to adopt the ``PairableDevice`` protocol for your device.
/// Optionally you can adopt ``BatteryPoweredDevice`` if your device supports the
/// [`BatteryService`](../GroveBluetoothServices/BluetoothServices.docc/BluetoothServices.md).
/// Once your device is loaded, register it with the `PairedDevices` module by calling the ``configure(device:accessing:_:_:)`` method.
///
/// - Important: Don't forget to configure the `PairedDevices` module in
///   your [`GroveAppDelegate`](../Grove/Grove.docc/Grove.md).
///
/// ```swift
/// import GroveDevices
///
/// class MyDevice: PairableDevice {
///     @DeviceState(\.id) var id
///     @DeviceState(\.name) var name
///     @DeviceState(\.state) var state
///     @DeviceState(\.advertisementData) var advertisementData
///     @DeviceState(\.nearby) var nearby
///
///     @Service var deviceInformation = DeviceInformationService()
///
///     @DeviceAction(\.connect) var connect
///     @DeviceAction(\.disconnect) var disconnect
///
///     var isInPairingMode: Bool {
///         // determine if a nearby device is in pairing mode
///     }
///
///     @Dependency private var pairedDevices: PairedDevices?
///
///     required init() {}
///
///     func configure() {
///         pairedDevices?.configure(device: self, accessing: $state, $advertisementData, $nearby)
///     }
///
///     func handleSuccessfulPairing() { // called on events where a device can be considered paired (e.g., incoming notifications)
///         pairedDevices?.signalDevicePaired(self)
///     }
/// }
/// ```
///
/// - Tip: To display and manage paired devices and support adding new paired devices, you can use the full-featured
/// [`DevicesView`](../GroveDevicesUI/GroveDevicesUI.docc/GroveDevicesUI.md).
///
/// ## Topics
///
/// ### Configuring Paired Devices
/// - ``init()``
///
/// ### Register Devices
/// - ``configure(device:accessing:_:_:)``
///
/// ### Paired Devices
/// - ``showAccessoryDiscovery()``
/// - ``pairedDevices``
///
/// ### Forget Paired Device
/// - ``forgetDevice(id:)-1zdk2``
///
/// ### Manage Paired Devices
/// - ``isPaired(_:)``
/// - ``isConnected(device:)``
/// - ``updateName(for:name:)``
///
/// ### Accessory Setup Kit Pairing
/// - ``accessoryPickerPresented``
///
/// ### Manual Pairing
/// - ``shouldPresentDevicePairing``
/// - ``discoveredDevices``
/// - ``isScanningForNearbyDevices``
/// - ``pair(with:timeout:)``
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class PairedDevices: ServiceModule {
    private enum InternalEvents: Sendable {
        case legacyForget(deviceId: UUID)
        case showPicker(runnable: @Sendable () async -> Void) // need to pass a closure as we cannot yet use iOS 18 only types
    }

    private enum AccessorySetupKitMigrationState: String {
        /// Initial state.
        case notDetermined
        /// PairedDevices has devices that were paired without the AccessorySetupKit (e.g., previous versions).
        case needsMigration
        /// All devices were paired with the AccessorySetupKit.
        case complete
    }

    @AppStorage(DevicesStorage.everPairedOnceKey)
    @MainActor @ObservationIgnored private var everPairedDevice = false
    @AppStorage(DevicesStorage.accessorySetupKitMigrationKey)
    @MainActor @ObservationIgnored private var asKitMigrationState: AccessorySetupKitMigrationState = .notDetermined


    @Application(\.logger)
    @ObservationIgnored private var logger

    @Dependency(Bluetooth.self)
    @ObservationIgnored private var bluetooth: Bluetooth?
    // periphery:ignore - the @Dependency declaration alone makes the module system configure TipKit
    @Dependency(ConfigureTipKit.self)
    @ObservationIgnored private var tipKit

    @Dependency @ObservationIgnored private var _accessorySetup: [any Module]

    @available(iOS 18, *)
    private var accessorySetup: AccessorySetupKit? {
        // we cannot have stored properties with @available. Therefore, we add a level of indirection.
        guard let module = _accessorySetup.first else {
            return nil
        }
        guard let loadASKit = module as? LoadAccessorySetupKit else {
            fatalError("\(LoadAccessorySetupKit.self) was not injected into dependency tree.")
        }
        return loadASKit.accessorySetupKit
    }

    @MainActor private var modelContainer: ModelContainer?

    /// Determines if the device discovery sheet should be presented.
    ///
    /// This property is never set to `true` if the AccessorySetupKit is used for device discovery and pairing. In cases where the framework is not available or not configured,
    /// this property will be set to `true` to present a fallback way for discovering accessories.
    @MainActor public var shouldPresentDevicePairing = false

    @MainActor private var _discoveredDevices: OrderedDictionary<UUID, DiscoveredDevice> = [:]
    /// Collection of discovered devices indexed by their Bluetooth identifier.
    @MainActor public var discoveredDevices: [any PairableDevice] {
        _discoveredDevices.values.map { $0.device }
    }


    nonisolated(unsafe) private var _pairedDevices: OrderedDictionary<UUID, PairedDevice> = [:]
    private let devicesLock = NSLock()
    /// The collection of paired devices that are persisted on disk.
    @MainActor public var pairedDevices: [PairedDeviceInfo]? { // swiftlint:disable:this discouraged_optional_collection
        didLoadDevices
            ? Array(_pairedDevices.values.map { $0.info })
            : nil
    }

    @MainActor private var didLoadDevices = false

    /// Determine if Bluetooth is scanning to discovery nearby devices.
    ///
    /// Scanning is automatically started if there hasn't been a paired device or if the discovery sheet is presented.
    @MainActor public var isScanningForNearbyDevices: Bool {
        let shouldAutoStartSearching = pairedDevices?.isEmpty == true && !everPairedDevice
#if canImport(AccessorySetupKit) && !os(macOS)
        return if #available(iOS 18, *) {
            shouldPresentDevicePairing || (accessorySetup == nil && shouldAutoStartSearching)
        } else {
            shouldPresentDevicePairing || shouldAutoStartSearching
        }
#else
        return shouldPresentDevicePairing || shouldAutoStartSearching
#endif
    }

    private let stateSubscription = BluetoothCentralStateSubscription()
    /// Manages and handles ongoing device connection attempts.
    private let deviceConnections = DeviceConnections()
    private let internalEvents: (stream: AsyncStream<InternalEvents>, continuation: AsyncStream<InternalEvents>.Continuation)

    @MainActor @ObservationIgnored private var accessoryEventRegistration: AccessoryEventRegistration?

    /// PairedDevices needs a migration to AccessorySetupKit.
    ///
    /// If this property is true, the PairedDevices module needs a migration to use AccessorySetupKit by calling ``showAccessoryMigration()``.
    /// This property returns true if there were previously paired devices that were paired manually and require a migration to AccessorySetupKit.
    @MainActor public var needsAccessorySetupKitMigration: Bool {
        asKitMigrationState == .needsMigration
    }


    /// Initialize the Paired Devices Module.
    public required init() {
        self.internalEvents = AsyncStream.makeStream()
#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
        if AccessorySetupKit.supportedProtocols.contains(.bluetooth) {
            __accessorySetup = Dependency {
                // Dynamic dependencies are always loaded independent if the module was already supplied in the environment.
                // Therefore, we create a helper module, that loads the accessory setup kit module.
                LoadAccessorySetupKit()
            }
        }
#endif
    }


    /// Configures the Module.
    @_documentation(visibility: internal)
    @MainActor
    public func configure() {
        if bluetooth == nil {
            self.logger.warning("PairedDevices Module initialized without Bluetooth dependency!")
        }

        DevicesStorage.migratePreferences()

        let configuration: ModelConfiguration
#if targetEnvironment(simulator)
        configuration = ModelConfiguration(isStoredInMemoryOnly: true)
#else
        if let storageUrl = DevicesStorage.prepareStore(.pairedDevices, migratingFrom: LegacyStorage.pairedDevicesStore) {
            configuration = ModelConfiguration(url: storageUrl)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        }
#endif

        do {
            self.modelContainer = try ModelContainer(for: PairedDeviceInfo.self, configurations: configuration)
        } catch {
            self.modelContainer = nil
            self.logger.error("PairedDevices failed to initialize ModelContainer: \(error)")
        }

        self.fetchAllPairedInfos()
        self.syncDeviceIcons() // make sure assets are up to date

        var powerUpUsingASKit = false

#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
        if accessorySetup != nil {
            powerUpUsingASKit = true
        } else {
            logger.info("AccessorySetupKit is supported by the platform but `NSAccessorySetupKitSupports` doesn't declare support for Bluetooth.")
        }
#endif

        let hasPairedDevices = !self.devicesLock.withLock { _pairedDevices.isEmpty }
        if powerUpUsingASKit {
            // We use the ASKit activate event to power up the central if there are paired devices as we need control over it.
            switch asKitMigrationState {
            case .notDetermined:
                asKitMigrationState = hasPairedDevices ? .needsMigration : .complete
            case .needsMigration, .complete:
                break
            }

#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
            // power up accessory setup kit after we determined the migration state
            setupAccessoryChangeSubscription()
#endif
        } else {
            asKitMigrationState = .notDetermined // support downgrades
            if let bluetooth, hasPairedDevices {
                // otherwise, power up central and subscribe to state changes
                self.stateSubscription.subscribe(with: bluetooth)
            }
        }
    }

    public func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask {
                await self.stateSubscription.run { state in
                    self.handleBluetoothStateChanged(state)
                }
            }

            group.addTask {
                await self.deviceConnections.run()
            }

            group.addTask {
                await self.runEvents()
            }
        }
    }

    private func runEvents() async {
        for await event in self.internalEvents.stream {
            switch event {
            case let .legacyForget(deviceId):
                do {
                    try await forgetDevice(id: deviceId)
                } catch {
                    logger.error("Failed to forget device \(deviceId): \(error)")
                }
            case let .showPicker(body):
                await body()
            }
        }
    }

    /// Show the accessory discovery picker.
    ///
    /// Depending on availability, this method presents the discovery sheet of the AccessorySetupKit. If not available, this method sets ``shouldPresentDevicePairing`` to `true`
    /// which should be used to present the `AccessorySetupSheet` from `GroveDevicesUI`.
    @MainActor
    public func showAccessoryDiscovery() {
#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
        if accessorySetup != nil {
            showAccessorySetupPicker()
        } else {
            shouldPresentDevicePairing = true
        }
#else
        shouldPresentDevicePairing = true
#endif
    }

    /// Show the accessory picker to migrate existing devices.
    ///
    /// Use the ``needsAccessorySetupKitMigration`` flag to determine if the migration picker needs to be shown.
    @MainActor
    @available(iOS 18, *)
    public func showAccessoryMigration() {
#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
        guard accessorySetup != nil else {
            logger.error("AccessorySetupKit is unavailable on the platform or not configured.")
            return
        }

        self.showAccessoryMigrationPicker()
#endif
    }

    /// Determine if a device is currently connected.
    /// - Parameter deviceId: The Bluetooth device identifier.
    /// - Returns: Returns `true` if the device for the given identifier is currently connected.
    @MainActor
    public func isConnected(device deviceId: UUID) -> Bool {
        let device = devicesLock.withLock {
            _pairedDevices[deviceId]
        }
        return device?.peripheral?.state == .connected
    }

    /// Determine if a device is paired.
    /// - Parameter device: The device instance.
    /// - Returns: Returns `true` if the given device is paired.
    @MainActor
    public func isPaired<Device: PairableDevice>(_ device: Device) -> Bool {
        devicesLock.withLock {
            _pairedDevices[device.id] != nil
        }
    }

    /// Update the user-chosen name of a paired device.
    ///
    /// - Note: If your Accessory is managed through the AccessorySetupKit, please make sure to rename the accessory through AccessorySetupKit such that the
    ///     name is visible in the Settings App and other applications as well.
    ///
    /// - Parameters:
    ///   - deviceInfo: The paired device information for which to update the name.
    ///   - name: The new name.
    @MainActor
    public func updateName(for deviceInfo: PairedDeviceInfo, name: String) {
        logger.debug("Updated name for paired device \(deviceInfo.id): \(name) %")
        deviceInfo.name = name
    }

    /// Configure a device to be managed by this PairedDevices instance.
    /// - Parameters:
    ///   - device: The device instance to configure.
    ///   - state: The `@DeviceState` accessor for the `PeripheralState`.
    ///   - advertisements: The `@DeviceState` accessor for the current `AdvertisementData`.
    ///   - nearby: The `@DeviceState` accessor for the `nearby` flag.
    @MainActor
    public func configure<Device: PairableDevice>(
        device: Device,
        accessing state: DeviceStateAccessor<PeripheralState>,
        _ advertisements: DeviceStateAccessor<AdvertisementData>,
        _ nearby: DeviceStateAccessor<Bool>
    ) {
        // this might be called for a device we are currently discovering, or for a paired device we retrieved

        if bluetooth?.pairableDevice(identifier: Device.deviceTypeIdentifier) == nil {
            logger.warning("""
                           Device \(Device.self) was configured with the PairedDevices module but wasn't configured with the Bluetooth module. \
                           The device won't be able to be retrieved on a fresh app start. Please make sure the device is configured with Bluetooth.
                           """)
        }

        if let pairedDevice = devicesLock.withLock({ _pairedDevices[device.id] }) {
            // we retrieved the device of a paired device
            pairedDevice.updateUponConfiguration(of: device)
        }

        state.onChange { @MainActor [weak self, weak device] oldValue, newValue in
            guard let self, let device else {
                return
            }

            if let pairedDevice = devicesLock.withLock({ _pairedDevices[device.id] }) {
                pairedDevice.handleDeviceStateUpdated(for: device, old: oldValue, new: newValue)
            }
            if let discoveredDevice = _discoveredDevices[device.id] {
                discoveredDevice.handleDeviceStateUpdated(for: device, newValue)
            }
        }
        advertisements.onChange(initial: true) { @MainActor [weak self, weak device] _ in
            if let self, let device {
                handleAdvertisementChange(device)
            }
        }
        nearby.onChange { @MainActor [weak self, weak device] nearby in
            if let device, !nearby {
                // device discovery was cleared by GroveBluetooth
                self?.handleDiscardedDevice(device)
            }
        }

        if let batteryPowered = device as? any BatteryPoweredDevice {
            batteryPowered.battery.$batteryLevel.onChange { @MainActor [weak self, weak device] value in
                if let self, let device, let pairedDevice = devicesLock.withLock({ _pairedDevices[device.id] }) {
                    pairedDevice.updateBattery(for: device, percentage: value)
                }
            }
        }

        logger.debug("Registered device \(device.label), \(device.id) with PairedDevices")
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension PairedDevices: Module, EnvironmentAccessible, DefaultInitializable, @unchecked Sendable {}

// MARK: - Manual Discovery

@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
extension PairedDevices {
    private func handleAdvertisementChange<Device: PairableDevice>(_ device: Device) {
        guard device.isInPairingMode, !isPaired(device), _discoveredDevices[device.id] == nil else {
            return
        }


        self.logger.info(
            "Detected nearby \(Device.self) accessory\(device.advertisementData.manufacturerData.map { " with manufacturer data \($0.debugDescription)" } ?? "")"
        )

        let discoveredDevice = DiscoveredDevice(device: device)
        _discoveredDevices[device.id] = discoveredDevice
    }

    private func handleDiscardedDevice<Device: PairableDevice>(_ device: Device) {
        let removed = _discoveredDevices.removeValue(forKey: device.id)
        if removed != nil {
            self.logger.debug("\(Device.self) \(device.label) was discarded from discovered devices.")
        }
    }

    /// Signal that a device is considered paired.
    ///
    /// You call this method from your device implementation on events that indicate that the device was successfully paired.
    /// - Note: This method does nothing if there is currently no ongoing pairing session for a device.
    /// - Parameter device: The device that can be considered paired and might have an ongoing pairing session.
    /// - Returns: Returns `true` if there was an ongoing pairing session and the device is now paired.
    @discardableResult
    public func signalDevicePaired(_ device: some PairableDevice) -> Bool {
        guard let discoveredDevice = _discoveredDevices[device.id] else {
            return false
        }

        return discoveredDevice.signalDevicePaired(device)
    }

    /// Pair with a recently discovered device.
    ///
    /// This method pairs with a currently advertising Bluetooth device.
    /// - Note: The ``PairableDevice/isInPairingMode`` property determines if the device is currently pairable.
    ///
    /// The implementation verifies that the device is ``PairableDevice/isInPairingMode``, is currently disconnected and ``PairableDevice/nearby``.
    /// It automatically connects to the device to start pairing. Pairing has a 15 second timeout by default.
    /// Pairing is considered successful once ``signalDevicePaired(_:)`` is called by the device. It is considered unsuccessful if the device
    /// disconnects prior to this call.
    /// - Important: A successful pairing cannot be determined automatically and is specific to a device. You must manually call
    ///     ``signalDevicePaired(_:)`` to signal that a device is successfully paired (e.g., every time the device sends a notification for
    ///     a given characteristic).
    /// - Parameters:
    ///   - device: The device to pair with this module.
    ///   - timeout: The duration after which the pairing attempt times out.
    /// - Throws: Throws a ``DevicePairingError`` if not successful.
    public func pair(with device: some PairableDevice, timeout: Duration = .seconds(15)) async throws {
        guard device.isInPairingMode else {
            throw DevicePairingError.notInPairingMode
        }

        guard let discoveredDevice = _discoveredDevices[device.id],
              case .disconnected = device.state,
              device.nearby else {
            throw DevicePairingError.invalidState
        }

        guard !discoveredDevice.hasContinuationAssigned else {
            throw DevicePairingError.busy
        }

        try await withThrowingDiscardingTaskGroup { group in
            // connect task
            group.addTask { @Sendable @GroveBluetooth in
                do {
                    try await device.connect()
                } catch let error as CancellationError {
                    discoveredDevice.clearPairingContinuationWithIntentionToResume()?.signalCancellation()
                    throw error
                }
            }

            group.addTask {
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled {
                    discoveredDevice.clearPairingContinuationWithIntentionToResume()?.signalTimeout()
                }
            }

            do {
                // waiting for task to signal pairing success by resuming the continuation
                try await withTaskCancellationHandler { // error thrown here will implicitly cancel all other child tasks
                    try await withCheckedThrowingContinuation { continuation in
                        discoveredDevice.assignContinuation(continuation)
                    }
                } onCancel: {
                    discoveredDevice.clearPairingContinuationWithIntentionToResume()?.signalCancellation()
                }
            } catch let error as CancellationError {
                // If we got cancelled while connecting, GroveBluetooth will make sure to disconnect the device anyways.
                // If we are just waiting for pairing to complete, we want to disconnect again.
                await device.disconnect()
                throw error
            }

            // if the connect task is still running above, we cancel the task group to disconnect the device
            group.cancelAll()
        }


        // the task group above should exit with a CancellationError anyways, but safe to double check here
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        await registerPairedDevice(device)
    }
}

// MARK: - Device Pairing

@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
extension PairedDevices {
    private func registerPairedDevice<Device: PairableDevice>(_ device: Device) async {
        everPairedDevice = true

        var batteryLevel: UInt8?
        if let batteryDevice = device as? any BatteryPoweredDevice {
            batteryLevel = batteryDevice.battery.batteryLevel
        }

        if device.deviceInformation.modelNumber == nil && device.deviceInformation.$modelNumber.isPresent {
            // make sure it isn't just a race condition that we haven't received a value yet
            do {
                let readModel = try await device.deviceInformation.$modelNumber.read()
                self.logger.info("ModelNumber was not present on device \(device.label), was read as \"\(readModel)\".")
            } catch {
                logger.debug("Failed to retrieve model number for device \(Device.self): \(error)")
            }
        }

        let (appearance, variantId) = Device.appearance.appearance { variant in
            variant.criteria.matches(name: device.name, advertisementData: device.advertisementData)
        }

        let deviceInfo = PairedDeviceInfo(
            id: device.id,
            deviceType: Device.deviceTypeIdentifier,
            name: appearance.name,
            model: device.deviceInformation.modelNumber,
            icon: appearance.icon,
            variantIdentifier: variantId,
            batteryPercentage: batteryLevel
        )

        let pairedDevice = PairedDevice(info: deviceInfo, assigning: device)

        persistPairedDevice(pairedDevice)
    }

    private func persistPairedDevice(_ pairedDevice: PairedDevice) {
        let wasFirstPairing = devicesLock.withLock {
            let wasFirstPairing = _pairedDevices.isEmpty
            _pairedDevices[pairedDevice.info.id] = pairedDevice
            return wasFirstPairing
        }

        if let modelContainer {
            modelContainer.mainContext.insert(pairedDevice.info)
            do {
                try modelContainer.mainContext.save()
            } catch {
                logger.warning("Failed to persist PairedDevice \(pairedDevice.info.id) due to \(error).")
            }
        } else {
            logger.warning("PairedDevice \(pairedDevice.info.name), \(pairedDevice.info.id) could not be persisted due to missing ModelContainer!")
        }

        _discoveredDevices.removeValue(forKey: pairedDevice.info.id)

        self.logger.debug("Device \(pairedDevice.info.name) with id \(pairedDevice.info.id) is now paired!")

        if wasFirstPairing, let bluetooth {
            self.stateSubscription.subscribe(with: bluetooth)
        }
    }

    /// Forget a paired device.
    /// - Parameter id: The Bluetooth peripheral identifier of a paired device.
    @available(*, deprecated, message: "Please use the async version of this method.")
    @_documentation(visibility: internal)
    public func forgetDevice(id: UUID, file: String = #fileID, line: UInt = #line) {
        logger.warning("Deprecated version of \(#function) got called from \(file):\(line). Please migrate to the async throwing version.")
        internalEvents.continuation.yield(.legacyForget(deviceId: id))
    }

    /// Forget a paired device.
    /// - Parameter id: The Bluetooth peripheral identifier of a paired device.
    public func forgetDevice(id: UUID) async throws {
#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
        let externallyManaged: Bool
        if let accessorySetup,
           let accessory = accessorySetup.accessories.first(where: { $0.bluetoothIdentifier == id }) {
            // this will trigger a disconnect
            try await accessorySetup.removeAccessory(accessory)
            externallyManaged = true
        } else {
            externallyManaged = false
        }
#else
        let externallyManaged = false
#endif

        self.removeDevice(id: id, externallyManaged: externallyManaged)
    }

    private func removeDevice(id: UUID, externallyManaged: Bool) {
        let (device, isEmpty) = devicesLock.withLock { () -> (PairedDevice?, Bool) in
            guard let device = _pairedDevices.removeValue(forKey: id) else {
                return (nil, _pairedDevices.isEmpty)
            }

            return (device, _pairedDevices.isEmpty)
        }

        guard let device else {
            return // this might be called twice, as the AccessorySetupKit will dispatch an event on manual removal
        }

        logger.debug("Removing device \(device.info.name), \(device.info.id) ...")

        // just make sure to remove it from discovered devices
        let discoveredDevice = _discoveredDevices.removeValue(forKey: id)
        discoveredDevice?.clearPairingContinuationWithIntentionToResume()?.signalDisconnect()

        modelContainer?.mainContext.delete(device.info)
        do {
            try modelContainer?.mainContext.save()
        } catch {
            logger.warning("Failed to persist device removal of \(device.info.id): \(error)")
        }

        device.removeDevice(manualDisconnect: !externallyManaged, cancelling: deviceConnections)

        logger.debug("Successfully removed device \(device.info.name), \(device.info.id)!")

        if isEmpty, let bluetooth {
            stateSubscription.cancel(bluetooth)
        }
    }
}


// MARK: - Paired Peripheral Management

@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
extension PairedDevices {
    private func fetchAllPairedInfos(previousPeripherals: [UUID: (any PairableDevice)] = [:]) {
        defer {
            didLoadDevices = true
        }

        guard let modelContainer else {
            return
        }

        let context = modelContainer.mainContext
        var allPairedDevices = FetchDescriptor<PairedDeviceInfo>(
            sortBy: [SortDescriptor(\.pairedAt)]
        )
        allPairedDevices.includePendingChanges = true

        do {
            let allPairedDevices = try context.fetch(allPairedDevices)
            let pairedDevices: OrderedDictionary<UUID, PairedDevice> = allPairedDevices.reduce(into: [:]) { partialResult, deviceInfo in
                partialResult[deviceInfo.id] = PairedDevice(info: deviceInfo, assigning: previousPeripherals[deviceInfo.id])
            }
            devicesLock.withLock {
                _pairedDevices = pairedDevices
            }
            logger.debug("Initialized PairedDevices with \(pairedDevices.count) paired devices: \(pairedDevices.map { $0.value.info.name }.joined(separator: ", "))")
        } catch {
            logger.error("Failed to fetch paired device info from disk: \(error)")
        }
    }

    func refreshPairedDevices() throws {
        let previousPeripherals = devicesLock.withLock {
            let peripherals = _pairedDevices.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key] = entry.value.peripheral
            }
            _pairedDevices.removeAll()
            return peripherals
        }
        didLoadDevices = false

        if let modelContainer, modelContainer.mainContext.hasChanges {
            try modelContainer.mainContext.save()
        }

        fetchAllPairedInfos(previousPeripherals: previousPeripherals)
    }

    private func syncDeviceIcons() {
        guard let bluetooth else {
            return
        }

        let configuredDevices = bluetooth.configuredPairableDevices()

        let pairedDevices = devicesLock.withLock {
            Array(_pairedDevices.values)
        }
        for pairedDevice in pairedDevices {
            let deviceInfo = pairedDevice.info
            guard let deviceType = configuredDevices[deviceInfo.deviceType] else {
                continue
            }

            if let migration = deviceType as? any DeviceVariantMigration.Type,
               case .variants = deviceType.appearance,
               deviceInfo.variantIdentifier == nil {
                let (appearance, variantId) = migration.selectAppearance(for: deviceInfo)
                deviceInfo.variantIdentifier = variantId
                deviceInfo.icon = appearance.icon
            } else {
                deviceInfo.icon = deviceType.appearance.deviceIcon(variantId: deviceInfo.variantIdentifier)
            }
        }
    }

    @GroveBluetooth
    private func handleBluetoothStateChanged(_ state: BluetoothState) {
        logger.debug("Bluetooth Module state is now \(state)")

        switch state {
        case .poweredOn:
            handleCentralPoweredOn()
        case .poweredOff, .unauthorized, .unsupported, .unknown:
            handleCentralPoweredOff()
        }
    }

    @GroveBluetooth
    private func handleCentralPoweredOn() {
        guard let bluetooth,
              case .poweredOn = bluetooth.state else {
            return
        }

        devicesLock.withLock {
            assert(!_pairedDevices.isEmpty, "Bluetooth State subscription doesn't need to be set up without any paired devices.")

            for device in self._pairedDevices.values {
                deviceConnections.connect(device: device, using: bluetooth)
            }
        }
    }

    @GroveBluetooth
    private func handleCentralPoweredOff() {
        let devicesPaired = devicesLock.withLock {
            guard !_pairedDevices.isEmpty else {
                return false
            }

            for device in _pairedDevices.values {
                deviceConnections.cancel(device: device, disconnect: nil)
            }

            return true
        }

        if devicesPaired {
            logger.debug("Successfully powered off PairedDevices and cancelled all connection attempts!")
        }
    }
}

// MARK: - Accessory Setup Kit

@available(iOS 18, macOS 15, watchOS 11, *)
extension PairedDevices {
    /// Determine if the accessory picker of the AccessorySetupKit is currently being presented.
    @MainActor public var accessoryPickerPresented: Bool {
        accessorySetup?.pickerPresented ?? false
    }

#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
    /// Retrieve the `ASAccessory` for a device identifier.
    /// - Parameter deviceId: The identifier for a paired bluetooth device.
    /// - Returns: The accessory or `nil` if the device is not managed by the AccessorySetupKit.
    @_spi(Internal)
    @MainActor
    public func accessory(for deviceId: UUID) -> ASAccessory? {
        if let accessorySetup {
            accessorySetup.accessories.first { accessory in
                accessory.bluetoothIdentifier == deviceId
            }
        } else {
            nil
        }
    }

    @MainActor
    private func setupAccessoryChangeSubscription() {
        self.accessoryEventRegistration = accessorySetup?.registerHandler { [weak self] event in
            guard let self else {
                return
            }

            logger.debug("Received accessory change: \(String(describing: event))")

            switch event {
            case .available:
                if let accessories = accessorySetup?.accessories {
                    handleSessionAvailable(for: accessories)
                }
            case let .added(accessory):
                handleAddedAccessory(accessory)
            case let .changed(accessory):
                updateAccessory(accessory)
            case let .removed(accessory):
                handleRemovedAccessory(accessory)
            case .migrationComplete:
                self.asKitMigrationState = .complete
                if let bluetooth {
                    self.stateSubscription.subscribe(with: bluetooth)
                }
            }
        }
    }

    @MainActor
    private func handleSessionAvailable(for accessories: [ASAccessory]) {
        for accessory in accessories {
            guard let uuid = accessory.bluetoothIdentifier else {
                continue
            }

            if let deviceInfo = devicesLock.withLock({ _pairedDevices[uuid] }) {
                // already paired, associate with the device info
                deviceInfo.info.accessory = accessory
            } else {
                logger.debug("Found available accessory that hasn't been paired: \(accessory)")
                handleAddedAccessory(accessory)
            }
        }

        if let bluetooth,
           case .complete = asKitMigrationState,
           devicesLock.withLock({ !_pairedDevices.isEmpty }) {
            stateSubscription.subscribe(with: bluetooth)
        }
    }

    @MainActor
    func showAccessorySetupPicker() {
        guard let bluetooth else {
            preconditionFailure("Tried to show accessory setup picker but Bluetooth module was not configured.")
        }

        guard let accessorySetup else {
            preconditionFailure("Tried to show accessory setup picker but AccessorySetupKit module was not configured.")
        }

        var displayItems: [ASPickerDisplayItem] = bluetooth.configuration.reduce(into: []) { partialResult, descriptor in
            guard descriptor.deviceType is any PairableDevice.Type else {
                return
            }

            switch descriptor.deviceType.appearance {
            case let .appearance(appearance):
                let descriptor = descriptor.discoveryCriteria.discoveryDescriptor
                let image = appearance.icon.uiImageScaledForAccessorySetupKit()
                partialResult.append(ASPickerDisplayItem(name: appearance.name, productImage: image, descriptor: descriptor))
            case let .variants(_, variants):
                for variant in variants {
                    let descriptor = descriptor.discoveryCriteria.discoveryDescriptor
                    variant.criteria.apply(to: descriptor)

                    let image = variant.icon.uiImageScaledForAccessorySetupKit()
                    partialResult.append(ASPickerDisplayItem(name: variant.name, productImage: image, descriptor: descriptor))
                }

                // with the AccessorySetupKit we can only pair known device variants.
            }
        }

        if case .needsMigration = asKitMigrationState {
            displayItems.append(contentsOf: self.buildMigrationItemsForExistingDevices())
        }

        internalEvents.continuation.yield(.showPicker(runnable: { @MainActor [logger, displayItems] in
            do {
                try await accessorySetup.showPicker(for: displayItems)
            } catch {
                logger.error("Failed to show setup picker: \(error)")
            }
        }))
    }

    @MainActor
    private func buildMigrationItemsForExistingDevices() -> [ASMigrationDisplayItem] {
        guard let bluetooth else {
            preconditionFailure("Tried to show accessory setup picker but Bluetooth module was not configured.")
        }

        let configuredDevices: [String: DeviceDiscoveryDescriptor] = bluetooth.configuration.reduce(into: [:]) { partialResult, descriptor in
            guard let pairableDevice = descriptor.deviceType as? any PairableDevice.Type else {
                return
            }
            partialResult[pairableDevice.deviceTypeIdentifier] = descriptor
        }

        return _pairedDevices.values.reduce(into: []) { partialResult, device in
            guard let descriptor = configuredDevices[device.info.deviceType] else {
                return
            }

            let appearance: Appearance
            if let migration = descriptor.deviceType as? any DeviceVariantMigration.Type,
               case .variants = descriptor.deviceType.appearance,
               device.info.variantIdentifier == nil {
                let (deviceAppearance, _) = migration.selectAppearance(for: device.info)
                appearance = deviceAppearance
            } else {
                appearance = descriptor.deviceType.appearance.appearance { $0.id == device.info.variantIdentifier }.appearance
            }

            let asDescriptor = descriptor.discoveryCriteria.discoveryDescriptor
            let image = appearance.icon.uiImageScaledForAccessorySetupKit()

            let item = ASMigrationDisplayItem(name: appearance.name, productImage: image, descriptor: asDescriptor)
            item.peripheralIdentifier = device.id

            partialResult.append(item)
        }
    }

    @MainActor
    func showAccessoryMigrationPicker() {
        guard let accessorySetup else {
            preconditionFailure("Tried to show accessory setup picker but AccessorySetupKit module was not configured.")
        }

        let migrationItems: [ASMigrationDisplayItem] = buildMigrationItemsForExistingDevices()

        internalEvents.continuation.yield(.showPicker(runnable: { @MainActor [logger] in
            do {
                try await accessorySetup.showPicker(for: migrationItems)
            } catch {
                logger.error("Failed to show setup picker: \(error)")
            }
        }))
    }

    @MainActor
    private func handleAddedAccessory(_ accessory: ASAccessory) {
        guard let bluetooth, let id = accessory.bluetoothIdentifier else {
            return
        }

        guard let deviceType = bluetooth.pairableDevice(matches: accessory.descriptor) else {
            logger.error("Could not match discovery description of paired device: \(id)")
            return
        }

        if case .needsMigration = self.asKitMigrationState,
           devicesLock.withLock({ self._pairedDevices[id] != nil }) {
            // If migration is done through the discovery picker, we might get an accessory added event we don't really need to process.
            // This also avoids that we override the iconography, as the descriptor doesn't quite match our expectation.
            logger.info("Received accessory added event for a migrated device \(accessory.displayName) as \(deviceType).")
            return
        }

        let (appearance, variantId) = deviceType.appearance.appearance { variant in
            variant.criteria.matches(descriptor: accessory.descriptor)
        }

        logger.debug("Pairing ASAccessory \(accessory.displayName) as \(deviceType) ...")

        let deviceInfo = PairedDeviceInfo(
            id: id,
            deviceType: deviceType.deviceTypeIdentifier,
            name: accessory.displayName, // should be the same as appearance.name, however, user might have renamed it already
            model: nil,
            icon: appearance.icon,
            variantIdentifier: variantId
        )
        deviceInfo.accessory = accessory

        let pairedDevice = PairedDevice(info: deviceInfo)

        // otherwise device retrieval is handled once bluetooth is powered on
        persistPairedDevice(pairedDevice)
    }

    @MainActor
    private func updateAccessory(_ accessory: ASAccessory) {
        guard let id = accessory.bluetoothIdentifier,
              let pairedDevice = devicesLock.withLock({ _pairedDevices[id] }) else {
            logger.error("Received a accessory update for \(accessory.displayName) \(accessory.bluetoothIdentifier?.uuidString ?? "<unknown>") but unable to find local paired device!")
            return // unknown device or not a bluetooth device
        }

        // allow to sync back name!
        pairedDevice.info.name = accessory.displayName
    }

    @MainActor
    private func handleRemovedAccessory(_ accessory: ASAccessory) {
        guard let id = accessory.bluetoothIdentifier else {
            return
        }

        self.removeDevice(id: id, externallyManaged: true)
    }

    /// Rename an accessory.
    ///
    /// This will present a picker from the AccessorySetupKit to rename the accessory.
    /// - Parameter accessory: The accessory.
    @MainActor
    @_spi(Internal)
    public func renameAccessory(for accessory: ASAccessory) async throws {
        guard let accessorySetup else {
            return // we wouldn't receive the event if it the module wouldn't be configured
        }

        logger.debug("Renaming accessory via AccessorySetupKit ...")
        do {
            try await accessorySetup.renameAccessory(accessory)
            logger.debug("Successfully renamed accessory.")
        } catch {
            logger.error("Failed to rename accessory managed by AccessorySetupKit (\(accessory)): \(error)")
            throw error
        }
    }
#endif
}

// MARK: Bluetooth

@available(iOS 18, macOS 15, watchOS 11, *)
extension PairedDevices {
    struct BluetoothCentralStateSubscription: Sendable {
        private enum Event: Sendable {
            case subscribe(Bluetooth)
            case cancel(Bluetooth)
        }

        private let logger: Logger
        private let input: (stream: AsyncStream<Event>, continuation: AsyncStream<Event>.Continuation)

        init() {
            self.logger = Logger(subsystem: "org.grovealliance.devices", category: "\(Self.self)")
            self.input = AsyncStream.makeStream()
        }

        func subscribe(with bluetooth: Bluetooth) {
            input.continuation.yield(.subscribe(bluetooth))
        }

        func cancel(_ bluetooth: Bluetooth) {
            input.continuation.yield(.cancel(bluetooth))
        }

        @GroveBluetooth
        func run(_ handler: @escaping @GroveBluetooth (BluetoothState) -> Void) async {
            final class Box {
                var registration: StateRegistration?
            }

            let box = Box()

            for await event in input.stream {
                switch event {
                case let .subscribe(bluetooth):
                    logger.debug("Setting up Bluetooth state subscription ...")
                    box.registration = bluetooth.registerStateHandler(handler)

                    // If Bluetooth is currently turned off in control center or not authorized anymore, we would want to keep central allocated
                    // such that we are notified about the bluetooth state changing.
                    bluetooth.powerOn()

                    handler(bluetooth.state)
                case let .cancel(bluetooth):
                    logger.debug("Cancelling state subscription and powering off bluetooth module.")
                    box.registration?.cancel()
                    box.registration = nil
                    bluetooth.powerOff()
                }
            }

            logger.debug("Bluetooth State Subscription service ended.")
        }
    }
}

@available(iOS 18, macOS 15, watchOS 11, *)
extension Bluetooth {
    nonisolated func pairableDevice(deviceTypeIdentifier: String) -> (any PairableDevice.Type)? {
        for descriptor in configuration {
            guard let pairableDevice = descriptor.deviceType as? any PairableDevice.Type,
                  pairableDevice.deviceTypeIdentifier == deviceTypeIdentifier else {
                continue
            }
            return pairableDevice
        }

        return nil
    }

    nonisolated func configuredPairableDevices() -> [String: any PairableDevice.Type] {
        configuration.reduce(into: [:]) { partialResult, descriptor in
            guard let pairableDevice = descriptor.deviceType as? any PairableDevice.Type else {
                return
            }
            partialResult[pairableDevice.deviceTypeIdentifier] = pairableDevice
        }
    }

    nonisolated fileprivate func pairableDevice(identifier deviceTypeIdentifier: String) -> (any PairableDevice.Type)? {
        for descriptor in self.configuration {
            guard let pairableDevice = descriptor.deviceType as? any PairableDevice.Type,
                  pairableDevice.deviceTypeIdentifier == deviceTypeIdentifier else {
                continue
            }

            return pairableDevice
        }

        return nil
    }

#if canImport(AccessorySetupKit) && !os(macOS) && !targetEnvironment(macCatalyst)
    @available(iOS 18, *)
    nonisolated fileprivate func pairableDevice(matches discoveryDescriptor: ASDiscoveryDescriptor) -> (any PairableDevice.Type)? {
        for descriptor in self.configuration {
            guard let pairableDevice = descriptor.deviceType as? any PairableDevice.Type,
                  descriptor.discoveryCriteria.matches(descriptor: discoveryDescriptor) else {
                continue
            }

            return pairableDevice
        }

        return nil
    }
#endif
}

// swiftlint:disable:this file_length

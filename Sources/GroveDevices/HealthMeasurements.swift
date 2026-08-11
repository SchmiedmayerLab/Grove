//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Grove
import GroveBluetooth
public import GroveBluetoothServices
import GroveLegacyIdentifiers
public import HealthKit
import OSLog
import SwiftData
import SwiftUI


/// Manage and process health measurements from nearby Bluetooth Peripherals.
///
/// Use the `HealthMeasurements` module to collect health measurements from nearby Bluetooth devices like connected weight scales or
/// blood pressure cuffs.
/// - Note: Implement your device as a [`BluetoothDevice`](../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md)
///     using [GroveBluetooth](../GroveBluetooth/GroveBluetooth.docc/GroveBluetooth.md).
///
/// To support `HealthMeasurements`, you need to adopt the ``HealthDevice`` protocol for your device.
/// One your device is loaded, register its measurement service with the `HealthMeasurements` module
/// by calling a suitable variant of `configureReceivingMeasurements(for:on:)`.
///
/// ```swift
/// import GroveDevices
///
/// class MyDevice: HealthDevice {
///     @Service var deviceInformation = DeviceInformationService()
///     @Service var weightScale = WeightScaleService()
///
///     @Dependency private var measurements: HealthMeasurements?
///
///     required init() {}
///
///     func configure() {
///         measurements?.configureReceivingMeasurements(for: self, on: weightScale)
///     }
/// }
/// ```
///
/// To display new measurements to the user and save them to your external data store, you can use
/// [`MeasurementsRecordedSheet`](../GroveDevicesUI/GroveDevicesUI.docc/GroveDevicesUI.md).
/// Below is a short code example.
///
/// ```swift
/// import GroveDevices
/// import GroveDevicesUI
///
/// struct MyHomeView: View {
///     @Environment(HealthMeasurements.self) private var measurements
///
///     var body: some View {
///         @Bindable var measurements = measurements
///         ContentView()
///             .sheet(isPresented: $measurements.shouldPresentMeasurements) {
///                 MeasurementsRecordedSheet { samples in
///                     // save the array of HKSamples
///                 }
///             }
///     }
/// }
/// ```
///
/// - Important: Don't forget to configure the `HealthMeasurements` module in
///     your [`GroveAppDelegate`](../Grove/Grove.docc/Grove.md).
///
/// ## Topics
///
/// ### Configuring Health Measurements
/// - ``init()``
///
/// ### Register Devices
/// - ``configureReceivingMeasurements(for:on:)-5e7b7``
/// - ``configureReceivingMeasurements(for:on:)-2iu4v``
///
/// ### Processing Measurements
/// - ``shouldPresentMeasurements``
/// - ``pendingMeasurements``
/// - ``discardMeasurement(_:)``
@available(iOS 18, macOS 15, watchOS 11, *)
@Observable
public final class HealthMeasurements: ServiceModule, EnvironmentAccessible, DefaultInitializable, @unchecked Sendable {
    public typealias WeightScaleKeyPath<Device> = any KeyPath<Device, WeightScaleService> & Sendable
    public typealias BloodPressureKeyPath<Device> = any KeyPath<Device, BloodPressureService> & Sendable

    private let logger = Logger(subsystem: "org.grovealliance.omron", category: "HealthMeasurements")

    /// Determine if UI components displaying pending measurements should be displayed.
    @MainActor public var shouldPresentMeasurements = false
    /// The current queue of pending measurements.
    ///
    /// The newest measurement is always prepended.
    /// To clear pending measurements call ``discardMeasurement(_:)``.
    @MainActor public private(set) var pendingMeasurements: [HealthKitMeasurement] = []

    @Dependency(Bluetooth.self)
    @ObservationIgnored private var bluetooth: Bluetooth?

    private var modelContainer: ModelContainer?

    /// Initialize the Health Measurements Module.
    public required init() {}

    /// Initialize the Health Measurements Module with mock measurements.
    /// - Parameter measurements: The list of measurements to inject.
    @_spi(TestingSupport)
    @MainActor
    public convenience init(mock measurements: [HealthKitMeasurement]) {
        self.init()
        self.pendingMeasurements = measurements
    }

    @_documentation(visibility: internal)
    public func configure() {
        let inMemoryStorage: Bool
#if targetEnvironment(simulator)
        inMemoryStorage = true
#else
        inMemoryStorage = false
#endif
        self.configure(inMemoryStorage: inMemoryStorage)
    }

    /// Configure the Module.
    @_documentation(visibility: internal)
    package func configure(inMemoryStorage: Bool) {
        let configuration: ModelConfiguration
        if inMemoryStorage {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else if let storageUrl = DevicesStorage.prepareStore(
            .healthMeasurements,
            migratingFrom: LegacyStorage.healthMeasurementsStore
        ) {
            configuration = ModelConfiguration(url: storageUrl)
        } else {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        }

        do {
            self.modelContainer = try ModelContainer(for: StoredMeasurement.self, configurations: configuration)
        } catch {
            self.modelContainer = nil
            self.logger.error("HealthMeasurements failed to initialize ModelContainer: \(error)")
            return
        }
    }

    public func run() async {
        await self.fetchMeasurements()
    }

    /// Configure receiving and processing weight measurements from the provided service.
    ///
    /// Configures the device's weight measurements to be processed by the Health Measurements module.
    ///
    /// - Parameters:
    ///   - device: The device on which the service is present.
    ///   - keyPath: A KeyPath to the Weight Scale service to register.
    public func configureReceivingMeasurements<Device: HealthDevice>(
        for device: Device,
        on keyPath: WeightScaleKeyPath<Device>
    ) {
        device[keyPath: keyPath].$weightMeasurement.onChange { @MainActor [weak self, weak device] measurement in
            guard let self, let device else {
                return
            }
            guard case .connected = device.state else {
                logger.debug("Ignored weight measurement that was received while connecting: \(String(describing: measurement))")
                return
            }

            let service = device[keyPath: keyPath]
            logger.debug("Received new weight measurement: \(String(describing: measurement))")
            handleNewMeasurement(.weight(measurement, service.features ?? []), from: device.hkDevice)
        }
    }

    /// Configure receiving and processing blood pressure measurements form the provided service.
    ///
    /// Configures the device's blood pressure measurements to be processed by the Health Measurements module.
    ///
    /// - Parameters:
    ///   - device: The device on which the service is present.
    ///   - keyPath: A KeyPath to the Blood Pressure service to register.
    public func configureReceivingMeasurements<Device: HealthDevice>(
        for device: Device,
        on keyPath: BloodPressureKeyPath<Device>
    ) {
        // make sure to not capture the device
        device[keyPath: keyPath].$bloodPressureMeasurement.onChange { @MainActor [weak self, weak device] measurement in
            guard let self, let device else {
                return
            }
            guard case .connected = device.state else {
                logger.debug("Ignored blood pressure measurement that was received while connecting: \(String(describing: measurement))")
                return
            }
            let service = device[keyPath: keyPath]
            logger.debug("Received new blood pressure measurement: \(String(describing: measurement))")
            handleNewMeasurement(.bloodPressure(measurement, service.features ?? []), from: device.hkDevice)
        }

        logger.debug("Registered device \(device.label), \(device.id) with HealthMeasurements")
    }

    @MainActor
    private func handleNewMeasurement(_ measurement: BluetoothHealthMeasurement, from source: HKDevice) {
        let id = loadMeasurement(measurement, form: source)
        guard let id else {
            return
        }

        if let modelContainer {
            let storeMeasurement = StoredMeasurement(associatedMeasurement: id, measurement: measurement, device: source)
            modelContainer.mainContext.insert(storeMeasurement)
        } else {
            logger.warning("Measurement \(id) could not be persisted on disk due to missing ModelContainer!")
        }

        shouldPresentMeasurements = true
    }

    @MainActor
    private func loadMeasurement(_ measurement: BluetoothHealthMeasurement, form source: HKDevice) -> UUID? {
        let healthKitMeasurement: HealthKitMeasurement
        switch measurement {
        case let .weight(measurement, feature):
            let sample = measurement.weightSample(source: source, resolution: feature.weightResolution)
            let bmiSample = measurement.bmiSample(source: source)
            let heightSample = measurement.heightSample(source: source, resolution: feature.heightResolution)
            logger.debug("Measurement loaded: \(String(describing: measurement))")

            healthKitMeasurement = .weight(sample, bmi: bmiSample, height: heightSample)
        case let .bloodPressure(measurement, _):
            let bloodPressureSample = measurement.bloodPressureSample(source: source)
            let heartRateSample = measurement.heartRateSample(source: source)

            guard let bloodPressureSample else {
                logger.debug("Discarding invalid blood pressure measurement ...")
                return nil
            }

            logger.debug("Measurement loaded: \(String(describing: measurement))")

            healthKitMeasurement = .bloodPressure(bloodPressureSample, heartRate: heartRateSample)
        }

        // prepend to pending measurements
        pendingMeasurements.insert(healthKitMeasurement, at: 0)
        return healthKitMeasurement.id
    }

    /// Discard a pending measurement.
    ///
    /// Measurements are discarded if they are no longer of interest. Either because the users discarded the measurements contents or
    /// if the measurement was processed otherwise (e.g., saved to an external data store).

    /// - Parameter measurement: The pending measurement to discard.
    /// - Returns: Returns `true` if the measurement was in the array of pending measurement, `false` if nothing was discarded.
    @MainActor
    @discardableResult
    public func discardMeasurement(_ measurement: HealthKitMeasurement) -> Bool {
        guard let index = self.pendingMeasurements.firstIndex(of: measurement) else {
            return false
        }
        let element = self.pendingMeasurements.remove(at: index)

        let id = element.id // we need to capture id, element.id results in #Predicate to not compile
        do {
            try modelContainer?.mainContext.delete(
                model: StoredMeasurement.self,
                where: #Predicate<StoredMeasurement> { $0.associatedMeasurement == id }
            )
        } catch {
            logger.error("Failed to remove measurement from storage: \(error)")
        }

        return true
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthMeasurements {
    @MainActor
    func refreshFetchingMeasurements() throws {
        pendingMeasurements.removeAll()
        if let modelContainer, modelContainer.mainContext.hasChanges {
            try modelContainer.mainContext.save()
        }
        fetchMeasurements()
    }

    @MainActor
    private func fetchMeasurements() {
        guard let modelContainer else {
            return
        }

        var fetchAll = FetchDescriptor<StoredMeasurement>(
            sortBy: [SortDescriptor(\.storageDate)]
        )
        fetchAll.includePendingChanges = true

        let context = modelContainer.mainContext
        let storedMeasurements: [StoredMeasurement]
        do {
            storedMeasurements = try context.fetch(fetchAll)
        } catch {
            logger.error("Failed to retrieve stored measurements from disk \(error)")
            return
        }

        for storedMeasurement in storedMeasurements {
            guard let id = loadMeasurement(storedMeasurement.healthMeasurement, form: storedMeasurement.device) else {
                context.delete(storedMeasurement)
                continue
            }

            // Note, we associate `storedMeasurements` by the HealthKit sample UUID.
            // However, when we redo the conversion, the identifier changes.
            // Therefore, we need to make sure to update all associated ids after loading.
            storedMeasurement.associatedMeasurement = id
        }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                logger.error("Failed to save updated measurement id associations: \(error)")
            }
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthMeasurements {
    /// Call in preview simulator wrappers.
    ///
    /// Loads a mock measurement to display in preview.
    /// - Parameters:
    ///   - weightMeasurement: The weight measurement that should be loaded.
    ///   - weightResolution: The weight resolution to use.
    ///   - heightResolution: The height resolution to use.
    @_spi(TestingSupport)
    @MainActor
    public func loadMockWeightMeasurement(
        weightMeasurement: WeightMeasurement = .mock(),
        weightResolution: WeightScaleFeature.WeightResolution = .resolution5g,
        heightResolution: WeightScaleFeature.HeightResolution = .resolution1mm
    ) {
        let device = MockDevice.createMockDevice(
            weightMeasurement: weightMeasurement,
            weightResolution: weightResolution,
            heightResolution: heightResolution
        )

        guard let measurement = device.weightScale.weightMeasurement else {
            preconditionFailure("Mock Weight Measurement was never injected!")
        }

        handleNewMeasurement(.weight(measurement, device.weightScale.features ?? []), from: device.hkDevice)
    }

    /// Call in preview simulator wrappers.
    ///
    /// Loads a mock measurement to display in preview.
    /// - Parameter bloodPressureMeasurement: The blood pressure measurement that should be loaded.
    @_spi(TestingSupport)
    @MainActor
    public func loadMockBloodPressureMeasurement(bloodPressureMeasurement: BloodPressureMeasurement = .mock()) {
        let device = MockDevice.createMockDevice(bloodPressureMeasurement: bloodPressureMeasurement)

        guard let measurement = device.bloodPressure.bloodPressureMeasurement else {
            preconditionFailure("Mock Blood Pressure Measurement was never injected!")
        }

        handleNewMeasurement(.bloodPressure(measurement, device.bloodPressure.features ?? []), from: device.hkDevice)
    }
}

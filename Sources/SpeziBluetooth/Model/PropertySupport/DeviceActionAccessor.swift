//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Interact with a Device Action.
@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
public struct DeviceActionAccessor<Action: _BluetoothPeripheralAction> {
    private let storage: DeviceAction<Action>.Storage

    init(_ storage: DeviceAction<Action>.Storage) {
        self.storage = storage
    }


    /// Inject a custom action handler for previewing purposes.
    ///
    /// This method can be used to inject a custom handler for the device action.
    /// This is particularly helpful when writing SwiftUI previews or doing UI testing.
    ///
    /// - Parameter action: The action to inject.
    @_spi(TestingSupport)
    public func inject(_ action: Action.ClosureType) {
        storage.testInjections.storeIfNilThenLoad(.init()).injectedClosure = action
    }
}


@available(iOS 17, macOS 14, macCatalyst 17, tvOS 17, watchOS 10, visionOS 1, *)
extension DeviceActionAccessor: Sendable {}

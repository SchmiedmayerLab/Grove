//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseStorage
public import Grove
import GroveFirebaseConfiguration


/// Configures the Firebase Storage that can then be used within any application via `Storage.storage()`.
///
/// The `FirebaseStorageConfiguration` can be used to connect to the Firebase Storage emulator:
/// ```
/// class ExampleAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
///             // ...
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Configuration
/// - ``init()``
/// - ``init(emulatorSettings:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public final class FirebaseStorageConfiguration: Module, DefaultInitializable {
    // periphery:ignore - @Dependency registers the module dependency; the declaration's side effect is the point
    @Dependency(ConfigureFirebaseApp.self)
    private var configureFirebaseApp

    private let emulatorSettings: (host: String, port: Int)?
    

    /// Default configuration.
    public required convenience init() {
        self.init(emulatorSettings: nil)
    }
    
    /// Configure with emulator settings.
    /// - Parameters:
    ///   - emulatorSettings: The emulator settings. When using `nil`, FirebaseStorage module will connect to the FirebaseStorage cloud instance.
    public init(
        emulatorSettings: (host: String, port: Int)?
    ) {
        self.emulatorSettings = emulatorSettings
    }
    

    @_documentation(visibility: internal)
    public func configure() {
        if let emulatorSettings {
            Storage.storage().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }
    }
}

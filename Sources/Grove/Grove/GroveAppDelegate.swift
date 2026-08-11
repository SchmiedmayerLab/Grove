//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(SwiftUI)
public import SwiftUI


/// Configure the Grove-based application using the ``GroveAppDelegate/configuration`` property.
///
/// Set up the Grove framework in your `App` instance of your SwiftUI application using the ``GroveAppDelegate`` and the `@ApplicationDelegateAdaptor` property wrapper.
/// Use the `View.grove(_: GroveAppDelegate)` view modifier to apply your Grove configuration to the main view in your SwiftUI `Scene`:
/// ```swift
/// import Grove
/// import SwiftUI
///
///
/// @main
/// struct ExampleApp: App {
///     @ApplicationDelegateAdaptor(GroveAppDelegate.self) var appDelegate
///
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .grove(appDelegate)
///         }
///     }
/// }
/// ```
///
/// Register your different ``Module``s (or more sophisticated ``Module``s) using the ``GroveAppDelegate/configuration`` property.
/// ```swift
/// import Grove
///
///
/// class TemplateAppDelegate: GroveAppDelegate {
///     override var configuration: Configuration {
///         Configuration(standard: ExampleStandard()) {
///             // Add your `Module`s here ...
///        }
///     }
/// }
/// ```
///
/// The ``Module`` documentation provides more information about the structure of modules.
/// Refer to the ``Configuration`` documentation to learn more about the Grove configuration.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor // need to be made explicit, macOS NSApplicationDelegate has @MainActor individually specified for each method
open class GroveAppDelegate: NSObject, ApplicationDelegate, Sendable {
    private(set) static weak var appDelegate: GroveAppDelegate?
    static var notificationDelegate: GroveNotificationCenterDelegate? // swiftlint:disable:this weak_delegate

    /// Access the Grove instance.
    ///
    /// Use this property as a basis for creating your own APIs (e.g., providing SwiftUI Environment values that use information from Grove).
    /// To not make it directly available to the user.
    @_spi(APISupport)
    public static var grove: Grove? {
        GroveAppDelegate.appDelegate?._grove
    }

    private(set) var _grove: Grove? // swiftlint:disable:this identifier_name


    var grove: Grove {
        guard let grove = _grove else {
            let grove = Grove(from: configuration)
            self._grove = grove
            return grove
        }
        return grove
    }


    /// Register your different ``Module``s (or more sophisticated ``Module``s) using the ``GroveAppDelegate/configuration`` property,.
    ///
    /// The ``Standard`` acts as a central message broker in the application.
    /// ```swift
    /// import Grove
    ///
    ///
    /// class TemplateAppDelegate: GroveAppDelegate {
    ///     override var configuration: Configuration {
    ///         Configuration(standard: ExampleStandard()) {
    ///             // Add your `Module`s here ...
    ///        }
    ///     }
    /// }
    /// ```
    ///
    /// The ``Module`` documentation provides more information about the structure of modules.
    /// Refer to the ``Configuration`` documentation to learn more about the Grove configuration.
    open var configuration: Configuration {
        Configuration { }
    }

    // MARK: - Will Finish Launching

#if os(iOS) || os(visionOS) || os(tvOS)
    @available(*, deprecated, message: "Propagate deprecation warning.")
    open func application(
        _ application: UIApplication,
        // The usage of an optional collection is impossible to avoid as the function signature is defined by the `UIApplicationDelegate`
        // swiftlint:disable:next discouraged_optional_collection
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard !ProcessInfo.processInfo.isPreviewSimulator else {
            // If you are running an Xcode Preview and you have your global SwiftUI `App` defined with
            // the `@UIApplicationDelegateAdaptor` property wrapper, it will still instantiate the App Delegate
            // and call this willFinishLaunchingWithOptions delegate method. This results in an instantiation of Grove
            // and configuration of the respective modules. This might and will cause troubles with Modules that
            // are only meant to be instantiated once. Therefore, we skip execution of this if running inside the PreviewSimulator.
            // This is also not a problem, as there is no way to set up an application delegate within a Xcode preview.
            return true
        }

        precondition(_grove == nil, "\(#function) was called when Grove was already initialized. Unable to pass options!")

        var storage = GroveStorage()
        storage[LaunchOptionsKey.self] = launchOptions
        self._grove = Grove(from: configuration, storage: storage)
        Self.appDelegate = self

        // backwards compatibility
        grove.lifecycleHandler.willFinishLaunchingWithOptions(application, launchOptions: launchOptions ?? [:])

        setupNotificationDelegate()
        return true
    }
#elseif os(macOS)
    open func applicationWillFinishLaunching(_ notification: Notification) {
        guard !ProcessInfo.processInfo.isPreviewSimulator else {
            return // see note above for why we don't launch this within the preview simulator!
        }

        setupNotificationDelegate()
    }
#elseif os(watchOS)
    open func applicationDidFinishLaunching() {
        guard !ProcessInfo.processInfo.isPreviewSimulator else {
            return // see note above for why we don't launch this within the preview simulator!
        }

        precondition(_grove == nil, "\(#function) was called when Grove was already initialized. Unable to pass options!")
        setupNotificationDelegate()
    }
#endif

    // MARK: - Notifications

    open func application(_ application: _Application, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { // on macOS there is a missing MainActor annotation
            grove.remoteNotificationRegistrationSupport.handleDeviceTokenUpdate(deviceToken)

            // notify all notification handlers of an updated token
            for handler in grove.notificationTokenHandler {
                handler.receiveUpdatedDeviceToken(deviceToken)
            }
        }
    }

    open func application(_ application: _Application, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        MainActor.assumeIsolated { // on macOS there is a missing MainActor annotation
            grove.remoteNotificationRegistrationSupport.handleFailedRegistration(error)
        }
    }

#if !os(macOS)
    private func handleReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> BackgroundFetchResult {
        let handlers = grove.notificationHandler
        guard !handlers.isEmpty else {
            return .noData
        }

        let result: Set<BackgroundFetchResult> = await withTaskGroup(of: BackgroundFetchResult.self) { @MainActor group in
            for handler in handlers {
                group.addTask { @Sendable @MainActor in
                    await handler.receiveRemoteNotification(userInfo)
                }
            }

            var result: Set<BackgroundFetchResult> = []
            for await fetchResult in group {
                // don't ask why, but the `for in` or `reduce(into:_:)` versions trigger Swift 6 concurrency warnings, this one doesn't
                result.insert(fetchResult)
            }
            return result
        }

        if result.contains(.failed) {
            return .failed
        } else if result.contains(.newData) {
            return .newData
        } else {
            return .noData
        }
    }
#endif

#if os(iOS) || os(visionOS) || os(tvOS)
    open func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await handleReceiveRemoteNotification(userInfo)
    }
#elseif os(macOS)
    open func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        for handler in grove.notificationHandler {
            handler.receiveRemoteNotification(userInfo)
        }
    }
#elseif os(watchOS)
    open func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        await handleReceiveRemoteNotification(userInfo)
    }
#endif

    // MARK: - Legacy UIScene Integration

#if os(iOS) || os(visionOS) || os(tvOS)
    open func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = GroveSceneDelegate.self
        return sceneConfig
    }

    @available(*, deprecated, message: "Propagate deprecation warning.")
    open func applicationWillTerminate(_ application: UIApplication) {
        grove.lifecycleHandler.applicationWillTerminate(application)
    }
#endif
}
#endif

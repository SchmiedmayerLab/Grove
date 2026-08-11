//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import Foundation
public import GroveFoundation
import OrderedCollections
import RuntimeAssertions
#if canImport(Observation)
public import Observation
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Open-source framework for rapid development of modern, interoperable digital health applications.
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
///
/// ### Dynamically Loading Modules
///
/// While the above examples demonstrated how Modules are configured within your ``GroveAppDelegate``, they can also be loaded and unloaded dynamically based on demand.
/// To do so you, you need to access the global `Grove` instance from within your Module.
///
/// Below is a short code example:
/// ```swift
/// class ExampleModule: Module {
///     @Application(\.grove)
///     var grove
///
///     func userAuthenticated() {
///         grove.loadModule(AccountManagement())
///         // ...
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Properties
/// - ``logger``
/// - ``launchOptions``
/// - ``grove``
///
/// ### Remote Notifications
/// - ``registerRemoteNotifications``
/// - ``unregisterRemoteNotifications``
///
/// ### Dynamically Loading Modules
/// - ``loadModule(_:ownership:)``
/// - ``unloadModule(_:)``
#if canImport(Observation)
@Observable
#endif
@available(iOS 18, macOS 15, watchOS 11, *)
public final class Grove: Sendable { // swiftlint:disable:this type_body_length
    static let logger = Logger(subsystem: "org.grovealliance", category: "Grove")

    let standard: any Standard

    private let serviceGroup = ServiceModuleGroup(logger: Grove.logger)

    /// Guards `_storage`; held only for the duration of a single `storage` access
    private let storageLock = RWLock()

    /// A shared repository to store any `KnowledgeSource`s restricted to the ``GroveAnchor``.
    ///
    /// Every `Module` automatically conforms to `KnowledgeSource` and is stored within this storage object.
    ///
    /// - Note: All accesses are guarded by `storageLock`: reads return a snapshot taken under the read lock;
    ///     mutations run in place under the write lock via the `_modify` accessor.
    #if canImport(Observation)
    // we can't put just the `@ObservationIgnored` macro into the compiler directive
    // (the issue being that the @Observation macro above won't properly pick it up),
    // so we sadly need to declare the property twice...
    @ObservationIgnored nonisolated(unsafe) private var _storage: GroveStorage
    #else
    nonisolated(unsafe) private var _storage: GroveStorage
    #endif
    
    nonisolated var storage: GroveStorage {
        get {
            #if canImport(Observation)
            access(keyPath: \.storage)
            #endif
            return storageLock.withReadLock { _storage }
        }
        _modify {
            // `yield` cannot appear inside a closure, so withMutation and withWriteLock are unrolled by hand here.
            #if canImport(Observation)
            _$observationRegistrar.willSet(self, keyPath: \.storage)
            #endif
            storageLock._pthreadWriteLock()
            defer {
                storageLock._pthreadUnlock()
                #if canImport(Observation)
                _$observationRegistrar.didSet(self, keyPath: \.storage)
                #endif
            }
            yield &_storage
        }
    }

#if canImport(SwiftUI)
    /// Key is either a UUID for `@Modifier` or `@Model` property wrappers, or a `ModuleReference` for `EnvironmentAccessible` modifiers.
    @MainActor private var _viewModifiers: OrderedDictionary<AnyHashable, any ViewModifier> = [:]

    /// Array of all SwiftUI `ViewModifiers` collected using `_ModifierPropertyWrapper` from the configured ``Module``s.
    ///
    /// Any changes to this property will cause a complete re-render of the SwiftUI view hierarchy. See `GroveViewModifier`.
    @MainActor var viewModifiers: [any ViewModifier] {
        _viewModifiers
            // View modifiers of inner-most modules are added first due to the dependency order.
            // However, we want view modifiers of dependencies to be available for inside view modifiers of the parent
            // (e.g., ViewModifier should be able to require the @Environment(...) value of the @Dependency).
            // This is why we need to reverse the order here.
            .reversed()
            .reduce(into: []) { partialResult, entry in
                partialResult.append(entry.value)
            }
    }

    /// A collection of ``Grove/Grove`` `LifecycleHandler`s.
    @available(
        *,
         deprecated,
         message: """
             Please use the new @Application property wrapper to access delegate functionality. \
             Otherwise use the SwiftUI onReceive(_:perform:) for UI related notifications.
             """
    )
    
    @MainActor package var lifecycleHandler: [any LifecycleHandler] {
        modules.compactMap { module in
            module as? any LifecycleHandler
        }
    }

    @MainActor var notificationTokenHandler: [any NotificationTokenHandler] {
        modules.compactMap { module in
            module as? any NotificationTokenHandler
        }
    }

    @MainActor var notificationHandler: [any NotificationHandler] {
        modules.compactMap { module in
            module as? any NotificationHandler
        }
    }
#endif
    
    @_spi(APISupport)
    public var modules: [any Module] {
        storage.collect(allOf: (any AnyStoredModules).self)
            .reduce(into: []) { partialResult, modules in
                partialResult.append(contentsOf: modules.anyModules)
            }
    }

    @MainActor private var implicitlyCreatedModules: Set<ModuleReference> {
        get {
            storage[ImplicitlyCreatedModulesKey.self]
        }
        set {
            if newValue.isEmpty {
                storage[ImplicitlyCreatedModulesKey.self] = nil
            } else {
                storage[ImplicitlyCreatedModulesKey.self] = newValue
            }
        }
    }
    

    @_spi(APISupport)
    @MainActor
    public convenience init(from configuration: Configuration, storage: consuming GroveStorage = GroveStorage()) {
        self.init(standard: configuration.standard, modules: configuration.modules.elements, storage: storage)
    }
    
    
    /// Create a new Grove instance.
    ///
    /// - Parameters:
    ///   - standard: The standard to use.
    ///   - modules: The collection of modules to initialize.
    ///   - storage: Optional, initial storage to inject.
    @MainActor
    package init(
        standard: any Standard,
        modules: [any Module],
        storage: consuming GroveStorage = GroveStorage()
    ) {
        self.standard = standard
        self._storage = consume storage

        do {
            try self.loadModules(modules, ownership: .grove)
            // load standard separately, such that all module loading takes precedence
            try self.loadModules([standard], ownership: .grove)
        } catch {
            preconditionFailure(error.description)
        }
    }
    
    /// Run the Grove service lifecycle.
    @_spi(APISupport)
    public func run() async {
        await serviceGroup.run()
    }

    /// Load a new Module.
    ///
    /// Loads a new Grove ``Module`` resolving all dependencies.
    /// - Note: Trying to load the same ``Module`` instance multiple times results in a runtime crash.
    ///
    /// - Important: While ``Module/Modifier`` and ``Module/Model`` properties and the ``EnvironmentAccessible`` protocol
    ///     are generally supported with dynamically loaded Modules, they will cause the global SwiftUI view hierarchy to re-render.
    ///     This might be undesirable und will cause interruptions. Therefore, avoid dynamically loading Modules with these properties.
    ///
    /// - Parameters:
    ///   - module: The new Module instance to load.
    ///   - ownership: Define the type of ownership when loading the module.
    ///
    /// ## Topics
    /// ### Ownership
    /// - ``ModuleOwnership``
    @MainActor
    public func loadModule(_ module: any Module, ownership: ModuleOwnership = .grove) {
        do {
            try loadModules([module], ownership: ownership)
        } catch {
            fatalError(error.description)
        }
    }

    @MainActor
    func loadModules(_ modules: [any Module], ownership: ModuleOwnership) throws(GroveModuleError) {
        precondition(Self.moduleInitContext == nil, "Modules cannot be loaded within the `configure()` method.")

        purgeWeaklyReferenced()

        let requestedModules = Set(modules.map { ModuleReference($0) })
        logger.debug("Loading module(s) \(modules.map { "\(type(of: $0))" }.joined(separator: ", ")) ...")


        let existingModules = self.modules

        let dependencyManager = DependencyManager(modules, existing: existingModules)
        do {
            try dependencyManager.resolve()
        } catch {
            throw .dependency(error)
        }

        implicitlyCreatedModules.formUnion(dependencyManager.implicitlyCreatedModules)
        
        // we pass through the whole list of modules once to collect all @Provide values
        for module in dependencyManager.initializedModules {
            withModuleInitContext(module.moduleDescription) {
                module.collectModuleValues(into: &storage)
            }
        }
        
        for module in dependencyManager.initializedModules {
            if requestedModules.contains(ModuleReference(module)) {
                // the policy only applies to the requested modules, all other are always managed and owned by Grove
                try self.initModule(module, ownership: ownership)
            } else {
                try self.initModule(module, ownership: .grove)
            }
        }
        
        
        // Newly loaded modules might have @Provide values that need to be updated in @Collect properties in existing modules.
        for existingModule in existingModules {
            existingModule.injectModuleValues(from: storage)
        }
    }
    
    /// Unload a Module.
    ///
    /// Unloads a ``Module`` from the Grove system.
    /// - Important: Unloading a ``Module`` that is still required by other modules results in a runtime crash.
    ///     However, unloading a Module that is the **optional** dependency of another Module works.
    ///
    /// Unloading a Module will recursively unload its dependencies that were not loaded explicitly.
    ///
    /// - Parameter module: The Module to unload.
    @MainActor
    public func unloadModule(_ module: any Module) {
        do {
            try _unloadModule(module)
        } catch {
            preconditionFailure(error.description)
        }
    }

    @MainActor
    func _unloadModule(_ module: any Module) throws(GroveModuleError) { // swiftlint:disable:this identifier_name
        precondition(Self.moduleInitContext == nil, "Modules cannot be unloaded within the `configure()` method.")

        purgeWeaklyReferenced()

        guard module.isLoaded(in: self) else {
            return // module is not loaded
        }

        logger.debug("Unloading module \(type(of: module)) ...")

        let dependents = retrieveDependingModules(module.dependencyReference, considerOptionals: false)
        if !dependents.isEmpty {
            throw GroveModuleError.moduleStillRequired(module: "\(type(of: module))", dependents: dependents.map { "\(type(of: $0))" })
        }
        
        module.clearModule(from: self)

        if let service = module as? any ServiceModule {
            // note that most of the grove property wrapper are racy upon de-initialization as soon as we un-inject (e.g., in the deinit as well)
            serviceGroup.cancel(service: service)
        }

        implicitlyCreatedModules.remove(ModuleReference(module))

#if canImport(SwiftUI)
        // this check is important. Change to viewModifiers re-renders the whole SwiftUI view hierarchy. So avoid to do it unnecessarily
        if _viewModifiers[ModuleReference(module)] != nil {
            var keys: Set<AnyHashable> = [ModuleReference(module)]
            keys.formUnion(module.viewModifierEntires.map { $0.0 })

            // remove all at once
            _viewModifiers.removeAll { entry in
                keys.contains(entry.key)
            }
        }
#endif
        
        // re-injecting all dependencies ensures that the unloaded module is cleared from optional Dependencies from
        // pre-existing Modules.
        let dependencyManager = DependencyManager([], existing: modules)
        do {
            try dependencyManager.resolve()
        } catch {
            preconditionFailure("Internal inconsistency. Repeated dependency resolve resulted in error: \(error)")
        }

        module.clear() // automatically removes @Provide values and recursively unloads implicitly created modules
    }

    /// Initialize a Module.
    ///
    /// Call this method to initialize a Module, injecting necessary information into Grove property wrappers.
    ///
    /// - Parameters:
    ///   - module: The module to initialize.
    ///   - ownership: Define the type of ownership when loading the module.
    @MainActor
    private func initModule(_ module: any Module, ownership: ModuleOwnership) throws(GroveModuleError) {
        precondition(!module.isLoaded(in: self), "Tried to initialize Module \(type(of: module)) that was already loaded!")

        do {
            try withModuleInitContext(module.moduleDescription) { () throws(GrovePropertyError) in
                try module.inject(grove: self)

                // supply modules values to all @Collect
                module.injectModuleValues(from: storage)

                module.configure()

                switch ownership {
                case .grove:
                    module.storeModule(into: self)
                case .external:
                    module.storeWeakly(into: self)
                }

                if let service = module as? any ServiceModule {
                    // Note: we still load modules with external ownership here.
                    serviceGroup.run(service: service)
                }

#if canImport(SwiftUI)
                // If a module is @Observable, we automatically inject it view the `ModelModifier` into the environment.
                if let observable = module as? any EnvironmentAccessible {
                    // we can't guarantee weak references for EnvironmentAccessible modules
                    precondition(ownership != .external, "Modules loaded with self-managed policy cannot conform to `EnvironmentAccessible`.")
                    _viewModifiers[ModuleReference(module)] = observable.viewModifier
                }

                let modifierEntires: [(id: UUID, modifier: any ViewModifier)] = module.viewModifierEntires
                // this check is important. Change to viewModifiers re-renders the whole SwiftUI view hierarchy. So avoid to do it unnecessarily
                if !modifierEntires.isEmpty {
                    for entry in modifierEntires.reversed() { // reversed, as we re-reverse things in the `viewModifier` getter
                        _viewModifiers.updateValue(entry.modifier, forKey: entry.id)
                    }
                }
#endif
            }
        } catch {
            throw .property(error)
        }
    }

    /// Determine if a application property is stored as a copy in a `@Application` property wrapper.
    func createsCopy<Value>(_ keyPath: KeyPath<Grove, Value>) -> Bool {
        keyPath == \.logger // loggers are created per Module.
            || keyPath == \.launchOptions
    }

    @MainActor
    private func retrieveDependingModules(_ dependency: DependencyReference, considerOptionals: Bool) -> [any Module] {
        var result: [any Module] = []

        for module in modules {
            switch module.dependencyRelation(to: dependency) {
            case .dependent:
                result.append(module)
            case .optional:
                if considerOptionals {
                    result.append(module)
                }
            case .unrelated:
                continue
            }
        }

        return result
    }

    @MainActor
    func handleDependencyUninjection<M: Module>(of dependency: M) {
        let dependencyReference = dependency.dependencyReference

        guard implicitlyCreatedModules.contains(dependencyReference.reference) else {
            // we only recursively unload modules that have been created implicitly
            return
        }

        guard retrieveDependingModules(dependencyReference, considerOptionals: true).isEmpty else {
            return
        }

        unloadModule(dependency)
    }

    @MainActor
    func handleCollectedValueRemoval<Value>(for id: UUID, of type: Value.Type) {
        var entries = storage[CollectedModuleValues<Value>.self]
        let removed = entries.removeValue(forKey: id)
        guard removed != nil else {
            return
        }
        storage[CollectedModuleValues<Value>.self] = entries
        for module in modules {
            module.injectModuleValues(from: storage)
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    func handleViewModifierRemoval(for id: UUID) {
        if _viewModifiers[id] != nil {
            _viewModifiers.removeValue(forKey: id)
        }
    }
    #endif

    func retrieveDependencyReplacement<M: Module>(for type: M.Type) -> M? {
        guard let storedModules = storage[StoredModulesKey<M>.self] else {
            return nil
        }
        let replacement = storedModules.retrieveFirstAvailable()
        storedModules.removeNilReferences(in: &storage) // if we ask for a replacement, there is opportunity to clean up weak reference objects
        return replacement
    }

    /// Iterates through weakly referenced modules and purges any nil references.
    ///
    /// These references are purged lazily. This is generally no problem because the overall overhead will be linear.
    /// If you load `n` modules with self-managed storage policy and then all `n` modules will eventually be deallocated, there might be `n` weak references still stored
    /// till the next module interaction is performed (e.g., new module is loaded or unloaded).
    private func purgeWeaklyReferenced() {
        storage
            .collect(allOf: (any AnyStoredModules).self)
            .forEach { storedModules in
                storedModules.removeNilReferences(in: &storage)
            }
    }
    
    @_spi(APISupport)
    @inlinable
    public func module<M: Module>(_ moduleType: M.Type = M.self) -> M? {
        modules.first { type(of: $0) == moduleType.self } as? M
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Module {
    @MainActor
    fileprivate func storeModule(into grove: Grove) {
        storeDynamicReference(.element(self), into: grove)
    }

    @MainActor
    fileprivate func storeWeakly(into grove: Grove) {
        storeDynamicReference(.weakElement(self), into: grove)
    }

    @MainActor
    fileprivate func storeDynamicReference(_ module: DynamicReference<Self>, into grove: Grove) {
        if grove.storage.contains(StoredModulesKey<Self>.self) {
            // swiftlint:disable:next force_unwrapping
            grove.storage[StoredModulesKey<Self>.self]!.updateValue(module, forKey: self.reference)
        } else {
            grove.storage[StoredModulesKey<Self>.self] = StoredModulesKey(module, forKey: reference)
        }
    }

    @MainActor
    fileprivate func isLoaded(in grove: Grove) -> Bool {
        guard let storedModules = grove.storage[StoredModulesKey<Self>.self] else {
            return false
        }
        return storedModules.contains(reference)
    }

    @MainActor
    fileprivate func clearModule(from grove: Grove) {
        guard var storedModules = grove.storage[StoredModulesKey<Self>.self] else {
            return
        }
        storedModules.removeValue(forKey: reference)

        if storedModules.isEmpty {
            grove.storage[StoredModulesKey<Self>.self] = nil
        } else {
            grove.storage[StoredModulesKey<Self>.self] = storedModules
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension Grove {
    private static let initContextLock = NSLock()
    nonisolated(unsafe) private static var _moduleInitContext: ModuleDescription?

    private(set) static var moduleInitContext: ModuleDescription? {
        get {
            initContextLock.withLock {
                _moduleInitContext
            }
        }
        set {
            initContextLock.withLock {
                _moduleInitContext = newValue
            }
        }
    }

    @MainActor
    func withModuleInitContext<E: Error>(_ context: ModuleDescription, perform action: () throws(E) -> Void) throws(E) {
        Self.moduleInitContext = context
        defer {
            Self.moduleInitContext = nil
        }

        try action()
    }
}

// swiftlint:disable:this file_length

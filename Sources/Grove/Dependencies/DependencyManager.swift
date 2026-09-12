//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import RuntimeAssertions


/// Gather information about modules with dependencies.
@available(iOS 18, macOS 15, watchOS 11, *)
@MainActor
public class DependencyManager: Sendable {
    /// Collection of already initialized modules.
    private let existingModules: [any Module]
    /// We track the top level module instances to resolve the order for initialization.
    private let originalModules: [any Module]

    /// Collection of initialized Modules.
    ///
    /// Order is determined by the dependency tree. This represents the result of the dependency resolution process.
    private(set) var initializedModules: [any Module]
    /// List of implicitly created Modules.
    ///
    /// A List of `ModuleReference`s that where implicitly created (e.g., due to another module requesting it as a Dependency and
    /// conforming to ``DefaultInitializable``).
    /// This list is important to keep for the unload mechanism.
    private(set) var implicitlyCreatedModules: Set<ModuleReference> = []

    /// Collection of all modules with dependencies that are not yet processed.
    private var modulesWithDependencies: [any Module]


    /// The current search stack for the module being pushed.
    private var currentPushedModule: ModuleReference?
    private var searchStacks: [ModuleReference: [any Module.Type]] = [:]

    /// Required dependency edges collected during ``require(_:type:defaultValue:)``.
    ///
    /// Used to detect peer cycles (both modules listed in the configuration) that the search-stack
    /// algorithm misses when the dependency is already queued or initialized.
    private var requiredDependencyEdges: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    private var moduleTypeNames: [ObjectIdentifier: String] = [:]

    private var nextTypeOrderIndex: UInt64 = 0
    private var moduleTypeOrder: [ObjectIdentifier: UInt64] = [:]


    /// A ``DependencyManager`` in Grove is used to gather information about modules with dependencies.
    ///
    /// - Parameters:
    ///   - modules: The modules that should be resolved.
    ///   - existingModules: Collection of already initialized modules.
    init(_ modules: [any Module], existing existingModules: [any Module] = []) {
        // modules without dependencies are already considered resolved
        self.initializedModules = modules.filter { $0.dependencyDeclarations.isEmpty }

        self.modulesWithDependencies = modules.filter { !$0.dependencyDeclarations.isEmpty }

        self.originalModules = modules
        self.existingModules = existingModules
    }


    /// Resolves the dependency order.
    ///
    /// After calling `resolve()` you can safely access `initializedModules`.
    func resolve() throws(DependencyManagerError) {
        while let nextModule = modulesWithDependencies.first {
            try push(nextModule)
        }

        try detectRequiredDependencyCycles()

        try injectDependencies()
        assert(searchStacks.isEmpty, "`searchStacks` are not getting cleaned up!")
        assert(currentPushedModule == nil, "`currentPushedModule` is never reset!")
        assert(modulesWithDependencies.isEmpty, "modulesWithDependencies has remaining entries \(modulesWithDependencies)")

        try buildTypeOrder()

        initializedModules.sort { lhs, rhs in
            retrieveTypeOrder(for: lhs) < retrieveTypeOrder(for: rhs)
        }
    }

    private func buildTypeOrder() throws(DependencyManagerError) {
        var completed: Set<ObjectIdentifier> = []
        var inProgress: Set<ObjectIdentifier> = []
        var recursionStack: [any Module.Type] = []

        func nextEntry(for module: any Module.Type) {
            let id = ObjectIdentifier(module)
            guard moduleTypeOrder[id] == nil else {
                return // already tracked
            }
            moduleTypeOrder[id] = nextTypeOrderIndex
            nextTypeOrderIndex += 1
        }

        func depthFirstSearch(for module: any Module) throws(DependencyManagerError) {
            let typeId = ObjectIdentifier(type(of: module))

            if completed.contains(typeId) {
                return
            }
            if inProgress.contains(typeId) {
                let dependencyChain = recursionStack.map { String(describing: $0) }
                throw DependencyManagerError.searchStackCycle(
                    module: String(describing: recursionStack.last.unsafelyUnwrapped),
                    requestedModule: String(describing: type(of: module)),
                    dependencyChain: dependencyChain
                )
            }

            inProgress.insert(typeId)
            recursionStack.append(type(of: module))

            for declaration in module.dependencyDeclarations {
                for dependency in declaration.unsafeInjectedModules {
                    try depthFirstSearch(for: dependency)
                }
            }

            recursionStack.removeLast()
            inProgress.remove(typeId)
            completed.insert(typeId)
            nextEntry(for: type(of: module))
        }

        for module in originalModules {
            try depthFirstSearch(for: module)
        }
    }

    private func retrieveTypeOrder(for module: any Module) -> UInt64 {
        guard let order = moduleTypeOrder[ObjectIdentifier(type(of: module))] else {
            preconditionFailure("Failed to retrieve module order index for module of type \(type(of: module))")
        }
        return order
    }

    private func injectDependencies() throws(DependencyManagerError) {
        // We inject dependencies into existingModules as well as a new dependency might be an optional dependency from a existing module
        // that wasn't previously injected.
        for module in initializedModules + existingModules {
            for dependency in module.dependencyDeclarations {
                try dependency.inject(from: self, for: module)
            }
        }
    }

    /// Push a module on the search stack and resolve dependency information.
    private func push(_ module: any Module) throws(DependencyManagerError) {
        assert(currentPushedModule == nil, "Module already pushed. Did the algorithm turn into an recursive one by accident?")

        currentPushedModule = ModuleReference(module)
        searchStacks[ModuleReference(module), default: []]
            .append(type(of: module))

        for dependency in module.dependencyDeclarations {
            try dependency.collect(into: self) // leads to calls to `require(_:defaultValue:)`
        }

        finishSearch(for: module)
    }

    /// Communicate a requirement to a `DependencyManager`
    /// - Parameters:
    ///   - dependency: The type of the dependency that should be resolved.
    ///   - defaultValue: A default instance of the dependency that is used when the `dependencyType` is not present in the `initializedModules` or `modulesWithDependencies`.
    func require<M: Module>(_ dependency: M.Type, type dependencyType: DependencyType, defaultValue: (() -> M)?) throws(DependencyManagerError) {
        try testForSearchStackCycles(M.self)

        if dependencyType.isRequired {
            recordRequiredDependencyEdge(to: M.self)
        }

        // 1. Check if it is actively requested to load this module.
        if case .load = dependencyType {
            guard let defaultValue else {
                return // doesn't make sense, just ignore that
            }

            implicitlyCreate(defaultValue)
            return
        }

        // 2. Return if the depending module is already initialized or being initialized.
        if initializedModules.contains(where: { type(of: $0) == M.self })
            || existingModules.contains(where: { type(of: $0) == M.self })
            || modulesWithDependencies.contains(where: { type(of: $0) == M.self }) {
            return
        }


        // 3. Otherwise, check if there is a default value we can implicitly load
        if let defaultValue {
            implicitlyCreate(defaultValue)
        } else if case .required = dependencyType,
                  let defaultInit = dependency as? any DefaultInitializable.Type,
                  let module = defaultInit.init() as? M {
            implicitlyCreate {
                module
            }
        }
    }

    /// Retrieve a resolved dependency for a given type.
    ///
    /// - Parameters:
    ///   - module: The ``Module`` type to return.
    ///   - optional: Flag indicating if it is a optional return.
    /// - Returns: Returns the Module instance. Only optional, if `optional` is set to `true` and no Module was found.
    func retrieve<M: Module>(module: M.Type, type dependencyType: DependencyType, for owner: any Module) throws(DependencyManagerError) -> M? {
        guard let candidate = existingModules.first(where: { type(of: $0) == M.self })
                ?? initializedModules.first(where: { type(of: $0) == M.self }),
              let module = candidate as? M else {
            if !dependencyType.isOptional {
                throw DependencyManagerError.missingRequiredModule(module: "\(type(of: owner))", requiredModule: "\(M.self)")
            }
            return nil
        }

        return module
    }

    private func implicitlyCreate<M: Module>(_ module: () -> M) {
        let newModule = module()

        implicitlyCreatedModules.insert(ModuleReference(newModule))

        if newModule.dependencyDeclarations.isEmpty {
            initializedModules.append(newModule)
        } else {
            saveSearchStack(for: newModule)

            modulesWithDependencies.append(newModule) // appending for BFS
        }
    }

    private func finishSearch(for dependingModule: any Module) {
        currentPushedModule = nil
        searchStacks.removeValue(forKey: ModuleReference(dependingModule))


        let dependingModulesCount = modulesWithDependencies.count
        modulesWithDependencies.removeAll(where: { $0 === dependingModule })
        precondition(dependingModulesCount - 1 == modulesWithDependencies.count, "Unexpected reduction of modules.")

        initializedModules.append(dependingModule)
    }

    private func saveSearchStack<M: Module>(for module: M) {
        guard let currentPushedModule,
              let searchStack = searchStacks[currentPushedModule] else {
            return
        }
        
        // propagate the search stack such that we have it available when we call push for this module
        searchStacks[ModuleReference(module)] = searchStack
    }

    private func testForSearchStackCycles<M>(_ module: M.Type) throws(DependencyManagerError) {
        if let currentPushedModule {
            let searchStack = searchStacks[currentPushedModule, default: []]

            if searchStack.contains(where: { $0 == M.self }) {
                let module = "\(searchStack.last.unsafelyUnwrapped)"
                let dependencyChain = searchStack
                    .map { String(describing: $0) }
                throw DependencyManagerError.searchStackCycle(module: module, requestedModule: "\(M.self)", dependencyChain: dependencyChain)
            }
        }
    }

    private func recordRequiredDependencyEdge<M: Module>(to dependency: M.Type) {
        guard let currentPushedModule,
              let fromType = searchStacks[currentPushedModule]?.last else {
            return
        }

        let fromId = ObjectIdentifier(fromType)
        let toId = ObjectIdentifier(dependency)
        moduleTypeNames[fromId] = String(describing: fromType)
        moduleTypeNames[toId] = String(describing: dependency)
        requiredDependencyEdges[fromId, default: []].insert(toId)
    }

    /// Detects required dependency cycles that the search-stack algorithm cannot see.
    ///
    /// Peer modules that are both present in the configuration never extend the search stack when they
    /// require each other (``require(_:type:defaultValue:)`` returns early), so cycles like `A ↔ B`
    /// are found here instead.
    private func detectRequiredDependencyCycles() throws(DependencyManagerError) {
        var visited: Set<ObjectIdentifier> = []
        var inProgress: Set<ObjectIdentifier> = []
        var recursionStack: [ObjectIdentifier] = []

        func depthFirstSearch(_ node: ObjectIdentifier) throws(DependencyManagerError) {
            if inProgress.contains(node) {
                let cycleStart = recursionStack.firstIndex(of: node).unsafelyUnwrapped
                let dependencyChain = recursionStack[cycleStart...]
                    .map { moduleTypeNames[$0].unsafelyUnwrapped }
                throw DependencyManagerError.searchStackCycle(
                    module: moduleTypeNames[recursionStack.last.unsafelyUnwrapped].unsafelyUnwrapped,
                    requestedModule: moduleTypeNames[node].unsafelyUnwrapped,
                    dependencyChain: Array(dependencyChain)
                )
            }
            if visited.contains(node) {
                return
            }

            visited.insert(node)
            inProgress.insert(node)
            recursionStack.append(node)

            for neighbor in requiredDependencyEdges[node, default: []] {
                try depthFirstSearch(neighbor)
            }

            recursionStack.removeLast()
            inProgress.remove(node)
        }

        for node in requiredDependencyEdges.keys {
            try depthFirstSearch(node)
        }
    }
}

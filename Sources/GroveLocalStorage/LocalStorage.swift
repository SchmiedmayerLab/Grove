//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import Grove
import GroveFoundation
import GroveKeychainStorage
import Security


/// Encrypted on-disk storage of data in mobile applications.
///
/// You interact with the ``LocalStorage`` API by defining custom ``LocalStorageKey``s, which are used to store values into the storage, and fetch them.
/// The key also allows you to define how each individual entry should be stored: e.g., which encoding and encryption settings should be used.
///
/// ## Topics
///
/// ### Configuration
/// - ``init()``
///
/// ### Storing Elements
/// - ``store(_:for:)``
/// - ``store(_:for:configuration:)``
/// - ``modify(_:_:)``
/// - ``modify(_:decodingConfiguration:encodingConfiguration:_:)``
///
/// ### Loading Elements
/// - ``load(_:)``
/// - ``load(_:configuration:)``
///
/// ### Deleting Entries
/// - ``delete(_:)``
/// - ``deleteAll()``
@available(iOS 18, macOS 15, watchOS 11, *)
public final class LocalStorage: Module, DefaultInitializable, EnvironmentAccessible, @unchecked Sendable {
    @Dependency(KeychainStorage.self) private var keychainStorage
    @Application(\.logger) private var logger
    
    private let fileManager = FileManager.default
    private let resourceValueWriter: @Sendable (URL, Bool) throws -> Void
    /* private-but-tests */ let localStorageDirectory: URL
    private let encryptionAlgorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
    
    
    /// Configure the `LocalStorage` module.
    public required convenience init() {
        self.init(namespace: .app)
    }

    /// Creates a `LocalStorage` scoped to an explicit namespace.
    ///
    /// - Parameter namespace: Where the app's data lives.
    init(
        namespace: StorageNamespace,
        resourceValueWriter: @escaping @Sendable (URL, Bool) throws -> Void = LocalStorage.writeResourceValues
    ) {
        // Application Support is where app-created data the user does not manipulate directly belongs.
        // A namespace only fails to resolve outside an app bundle, where there is no sensible answer;
        // falling back keeps a command-line host working rather than trapping at launch.
        localStorageDirectory = (try? namespace.directory(.localStorage))
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LocalStorage")
        self.resourceValueWriter = resourceValueWriter
    }

    private static func writeResourceValues(at url: URL, excludedFromBackup: Bool) throws {
        var url = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = excludedFromBackup
        try url.setResourceValues(resourceValues)
    }
    
    
    @_documentation(visibility: internal)
    public func configure() {
        // Must precede directory creation: the relocation commits by renaming the legacy directory
        // onto the destination, which is impossible once the destination exists.
        guard Self.migrateIfNeeded(into: localStorageDirectory, from: Self.legacyDirectory, fileManager: fileManager) else {
            // Creating the directory now would make the next launch believe the migration already ran.
            logger.error("LocalStorage migration did not complete; leaving existing data in place.")
            return
        }
        do {
            try createLocalStorageDirectoryIfNecessary()
        } catch {
            logger.error("Unable to create LocalStorage directory: \(error)")
        }
    }
    
    
    private func createLocalStorageDirectoryIfNecessary() throws {
        guard !fileManager.fileExists(atPath: localStorageDirectory.path) else {
            return
        }
        try fileManager.createDirectory(atPath: localStorageDirectory.path, withIntermediateDirectories: true, attributes: nil)
    }
    
    
    // MARK: Store
    
    /// Put a value into the `LocalStorage`.
    ///
    /// - parameter value: The value which should be persisted. Passing `nil` will delete the most-recently-stored value.
    /// - parameter key: The ``LocalStorageKey`` with which the value should be associated.
    ///
    /// - Note: This operation will overwrite any previously-stored values for this key.
    public func store<Value>(_ value: Value?, for key: LocalStorageKey<Value>) throws {
        try key.withLock {
            if let value {
                try storeImp(value, for: key, context: Void?.none)
            } else {
                try deleteImp(key)
            }
        }
    }

    /// Atomically replaces a value when its currently persisted value matches `expectedValue`.
    ///
    /// The comparison and replacement execute while holding the storage key's lock. This is useful for
    /// acknowledgement tokens and other optimistic-concurrency operations where a stale writer must not
    /// advance durable state.
    ///
    /// - returns: `true` when the replacement was performed; `false` when the persisted value did not match.
    public func compareExchange<Value: Equatable>(
        expected expectedValue: Value?,
        desired desiredValue: Value?,
        for key: LocalStorageKey<Value>
    ) throws -> Bool {
        try key.withLock {
            let currentValue = try readImp(key, context: Void?.none)
            guard currentValue == expectedValue else {
                return false
            }
            if let desiredValue {
                try storeImp(desiredValue, for: key, context: Void?.none)
            } else {
                try deleteImp(key)
            }
            return true
        }
    }
    
    /// Put a value into the `LocalStorage`.
    ///
    /// - parameter value: The value which should be persisted. Passing `nil` will delete the most-recently-stored value.
    /// - parameter key: The ``LocalStorageKey`` with which the value should be associated.
    /// - parameter configuration: The encoding configuration used to encode the value.
    ///
    /// - Note: This operation will overwrite any previously-stored values for this key.
    public func store<Value>(
        _ value: Value?,
        for key: LocalStorageKey<Value>,
        configuration: Value.EncodingConfiguration
    ) throws where Value: EncodableWithConfiguration {
        try key.withLock {
            if let value {
                try storeImp(value, for: key, context: configuration)
            } else {
                try deleteImp(key)
            }
        }
    }
    
    
    /// - invariant: assumes that the key's write lock is held.
    private func storeImp<Value>(_ value: Value, for key: LocalStorageKey<Value>, context: some Any) throws {
        let data = try key.encode(value, context: context)
        let persistedData: Data
        if let keys = try key.setting.keys(from: keychainStorage) {
            guard SecKeyIsAlgorithmSupported(keys.publicKey, .encrypt, encryptionAlgorithm) else {
                throw LocalStorageError.encryptionNotPossible
            }
            var encryptError: Unmanaged<CFError>?
            guard let encryptedData = SecKeyCreateEncryptedData(
                keys.publicKey,
                encryptionAlgorithm,
                data as CFData,
                &encryptError
            ) as Data? else {
                throw LocalStorageError.encryptionNotPossible
            }
            persistedData = encryptedData
        } else {
            persistedData = data
        }

        try replaceStoredData(persistedData, for: key)
        key.informSubscribersAboutNewValue(value)
    }

    /// Stages bytes and their resource metadata together, then atomically replaces the visible file.
    /// If metadata preparation fails, an existing value remains byte-for-byte untouched.
    private func replaceStoredData(_ data: Data, for key: LocalStorageKey<some Any>) throws {
        let destination = fileURL(for: key)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString.lowercased()).staging"
        )
        do {
            try data.write(to: staging, options: .atomic)
            do {
                try resourceValueWriter(staging, key.setting.isExcludedFromBackup)
            } catch {
                throw LocalStorageError.failedToExcludeFromBackup
            }
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
            throw error
        }
    }
    
    
    // MARK: Load
    
    /// Load a value from the `LocalStorage`.
    ///
    /// - parameter key: The ``LocalStorageKey`` associated with the to-be-retrieved value.
    /// - returns: The most recent stored value associated with the key; `nil` if no such value exists.
    public func load<Value>(_ key: LocalStorageKey<Value>) throws -> Value? {
        try key.withLock {
            try readImp(key, context: Void?.none)
        }
    }
    
    /// Load a value from the `LocalStorage`.
    ///
    /// - parameter key: The ``LocalStorageKey`` associated with the to-be-retrieved value.
    /// - parameter configuration: The decoding configuration which should be used when decoding a value.
    /// - returns: The most recent stored value associated with the key; `nil` if no such value exists.
    public func load<Value>(
        _ key: LocalStorageKey<Value>,
        configuration: Value.DecodingConfiguration
    ) throws -> Value? where Value: DecodableWithConfiguration {
        try key.withLock {
            try readImp(key, context: configuration)
        }
    }
    
    
    /// Determines whether the `LocalStorage` contains a value for the specified key.
    public func hasEntry(for key: LocalStorageKey<some Any>) -> Bool {
        key.withLock {
            fileManager.fileExists(atPath: fileURL(for: key).path)
        }
    }
    
    
    /// - invariant: assumes that the key's read lock is held.
    private func readImp<Value>(_ key: LocalStorageKey<Value>, context: some Any) throws -> Value? {
        let fileURL = fileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)

        // Determine if the data should be decrypted or not:
        guard let keys = try key.setting.keys(from: keychainStorage) else {
            return try key.decode(from: data, context: context)
        }

        guard SecKeyIsAlgorithmSupported(keys.privateKey, .decrypt, encryptionAlgorithm) else {
            throw LocalStorageError.decryptionNotPossible
        }

        var decryptError: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(keys.privateKey, encryptionAlgorithm, data as CFData, &decryptError) as Data? else {
            throw LocalStorageError.decryptionNotPossible
        }

        return try key.decode(from: decryptedData, context: context)
    }
    
    
    // MARK: Delete
    
    /// Deletes the `LocalStorage` entry associated with `key`.
    ///
    /// ```swift
    /// do {
    ///     try localStorage.delete(.myStorageKey)
    /// } catch {
    ///     // Handle delete errors ...
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The ``LocalStorageKey`` identifying the entry which should be deleted.
    public func delete(_ key: LocalStorageKey<some Any>) throws {
        try key.withLock {
            try deleteImp(key)
        }
    }
    
    
    /// - invariant: assumes that the key's write lock is held
    private func deleteImp(_ key: LocalStorageKey<some Any>) throws {
        let fileURL = fileURL(for: key)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(atPath: fileURL.path)
                key.informSubscribersAboutNewValue(nil)
            } catch {
                throw LocalStorageError.deletionNotPossible
            }
        }
    }
    
    
    /// Deletes all data currently stored using the `LocalStorage` API.
    ///
    /// - Warning: This will delete all data currently stored using the `LocalStorage` API.
    /// - Note: This operation is not synchronized with reads or writes on individual storage keys.
    public func deleteAll() throws {
        try fileManager.removeItem(at: localStorageDirectory)
        try createLocalStorageDirectoryIfNecessary()
    }
    
    
    /// Deletes all entries whose key's satisfy the predicate
    ///
    /// - Note: This operation is not synchronized with reads or writes on individual storage keys.
    public func deleteAll(where predicate: (_ rawKey: String) -> Bool) throws {
        for url in try fileManager.contentsOfDirectory(
            at: localStorageDirectory,
            includingPropertiesForKeys: nil
        ) {
            let rawKey = url.deletingPathExtension().lastPathComponent
            if predicate(rawKey) {
                try fileManager.removeItem(at: url)
            }
        }
    }
    
    
    // MARK: Other
    
    /// Modify a stored value in place
    ///
    /// Use this function to perform an atomic mutation of an entry in the `LocalStorage`.
    ///
    /// - parameter key: The ``LocalStorageKey`` whose value should be mutated.
    /// - parameter transform: A mapping closure, which will be called with the current value stored for `key` (or `nil`, if no value is stored).
    ///     The value after the closure invocation will be stored into the `LocalStorage`, for the entry identified by `key`.
    ///     If the closure sets `value` to `nil`, the entry will be removed from the `LocalStorage`.
    ///
    /// - throws: if `transform` throws,
    public func modify<Value>(_ key: LocalStorageKey<Value>, _ transform: (_ value: inout Value?) throws -> Void) throws {
        try key.withLock {
            var value = try readImp(key, context: Void?.none)
            try transform(&value)
            if let value {
                try storeImp(value, for: key, context: Void?.none)
            } else {
                try deleteImp(key)
            }
        }
    }
    
    
    /// Modify a stored value in place
    ///
    /// Use this function to perform an atomic mutation of an entry in the `LocalStorage`.
    ///
    /// - parameter key: The ``LocalStorageKey`` whose value should be mutated.
    /// - parameter transform: A mapping closure, which will be called with the current value stored for `key` (or `nil`, if no value is stored).
    ///     The value after the closure invocation will be stored into the `LocalStorage`, for the entry identified by `key`.
    ///     If the closure sets `value` to `nil`, the entry will be removed from the `LocalStorage`.
    /// - parameter decodingConfiguration: The decoding configuration used to decode the stored value.
    /// - parameter encodingConfiguration: The encoding configuration used to encode the updated value.
    ///
    /// - throws: if `transform` throws,
    public func modify<Value: CodableWithConfiguration>(
        _ key: LocalStorageKey<Value>,
        decodingConfiguration: Value.DecodingConfiguration,
        encodingConfiguration: Value.EncodingConfiguration,
        _ transform: (_ value: inout Value?) throws -> Void
    ) throws {
        try key.withLock {
            var value = try readImp(key, context: decodingConfiguration)
            try transform(&value)
            if let value {
                try storeImp(value, for: key, context: encodingConfiguration)
            } else {
                try deleteImp(key)
            }
        }
    }
    
    
    // MARK: File Handling
    
    func fileURL(for storageKey: LocalStorageKey<some Any>) -> URL {
        let storageKey = storageKey.key
        return localStorageDirectory.appending(path: storageKey).appendingPathExtension("localstorage")
    }

    /// Returns persisted raw keys matching a prefix without decoding their values.
    ///
    /// This SPI supports cursor-reset implementations that must discover partitions which are not
    /// currently reported by their platform framework. Values remain accessible only through their
    /// original typed `LocalStorageKey`.
    @_spi(Internal)
    public func persistedRawKeys(withPrefix prefix: String) throws -> [String] {
        guard fileManager.fileExists(atPath: localStorageDirectory.path) else {
            return []
        }
        return try fileManager
            .contentsOfDirectory(at: localStorageDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "localstorage" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasPrefix(prefix) }
    }
}

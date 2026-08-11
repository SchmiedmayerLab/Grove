//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if os(iOS)
import Foundation
@testable import GroveAccessGuard
import GroveKeychainStorage
import GroveLegacyIdentifiers
import Testing


/// Losing a passcode here locks a user out of their own app with no recovery path, so these cover the
/// cases where a naive migration silently drops one.
///
/// The keychain needs an entitlement the plain unit-test host does not carry, so these run in the
/// UI-test app and on device, and skip elsewhere rather than reporting a failure that says nothing
/// about the code.
/// File scope, not a static on the suite: a `.enabled(if:)` trait that reads a member of the type the
/// `@Suite` macro is expanding is a circular reference, and the suite does not compile.
private let keychainIsAvailable: Bool = {
    let keychain = KeychainStorage()
    let probe = CredentialsTag.genericPassword(forService: "org.grovealliance.accessGuard.probe")
    do {
        try keychain.store(Credentials(username: "probe", password: "probe"), for: probe)
        try? keychain.deleteCredentials(withUsername: "probe", for: probe)
        return true
    } catch {
        return false
    }
}()


@Suite(.serialized, .enabled(if: keychainIsAvailable))
struct AccessGuardKeychainMigrationTests {
    private let keychain = KeychainStorage()

    private func reset() {
        try? keychain.deleteCredentials(withUsername: nil, for: .accessGuard)
        try? keychain.deleteCredentials(withUsername: nil, for: .legacyAccessGuard)
    }

    private func usernames(for tag: CredentialsTag) -> Set<String> {
        Set(((try? keychain.retrieveAllCredentials(withUsername: nil, for: tag)) ?? []).map(\.username))
    }

    @Test
    func movesEveryAccountOntoTheCurrentService() throws {
        reset()
        defer { reset() }
        for username in ["guard-1", "guard-2"] {
            try keychain.store(Credentials(username: username, password: "code-\(username)"), for: .legacyAccessGuard)
        }

        #expect(AccessGuardKeychainMigration.run(in: keychain))

        #expect(usernames(for: .accessGuard) == ["guard-1", "guard-2"])
        #expect(usernames(for: .legacyAccessGuard).isEmpty)
    }

    /// Biometric fallback passcodes are stored under identifiers that never appear in
    /// `AccessGuards.configs`, so a migration driven by the configuration would leave them behind.
    @Test
    func movesAccountsThatNoConfigurationMentions() throws {
        reset()
        defer { reset() }
        try keychain.store(Credentials(username: "unlisted-biometric-fallback", password: "code"), for: .legacyAccessGuard)

        #expect(AccessGuardKeychainMigration.run(in: keychain))

        #expect(usernames(for: .accessGuard) == ["unlisted-biometric-fallback"])
    }

    @Test
    func preservesThePasscodeItself() throws {
        reset()
        defer { reset() }
        try keychain.store(Credentials(username: "guard", password: "the-secret"), for: .legacyAccessGuard)

        #expect(AccessGuardKeychainMigration.run(in: keychain))

        let migrated = try keychain.retrieveCredentials(withUsername: "guard", for: .accessGuard)
        #expect(migrated?.password == "the-secret")
    }

    @Test
    func isIdempotent() throws {
        reset()
        defer { reset() }
        try keychain.store(Credentials(username: "guard", password: "code"), for: .legacyAccessGuard)

        #expect(AccessGuardKeychainMigration.run(in: keychain))
        #expect(AccessGuardKeychainMigration.run(in: keychain))

        #expect(usernames(for: .accessGuard) == ["guard"])
    }

    @Test
    func aFreshInstallSucceedsWithNothingToDo() {
        reset()
        defer { reset() }

        #expect(AccessGuardKeychainMigration.run(in: keychain))
        #expect(usernames(for: .accessGuard).isEmpty)
    }
}
#endif

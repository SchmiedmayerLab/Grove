//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
public import Grove
private import Synchronization


/// Manage Account events and notifications.
///
/// This module implements a notification system for Account-related events.
///
/// ## Topics
///
/// ### Subscribing to events
/// - ``events``
/// - ``Event``
///
/// ### Reporting events
/// Report events when implementing an `AccountService`.
/// - ``reportEvent(_:)``
@available(iOS 18, macOS 15, watchOS 11, *)
public final class AccountNotifications: Module, DefaultInitializable, EnvironmentAccessible, @unchecked Sendable {
    /// Describes an Account event.
    public enum Event: Sendable {
        /// A new account was associated due to a login or signup operation.
        ///
        /// - Note: In previous releases of the package, this case was named `associatedAccount`.
        case didAssociate(_ details: AccountDetails)
        
        /// The details of the currently associated account changed.
        case detailsChanged(_ old: AccountDetails, _ new: AccountDetails)
        
        /// The currently associated account is about to be logged out.
        ///
        /// Note that this event is not guaranteed to always be emitted;
        /// e.g., if the account was deleted on the backend and the account service is responding to that by disassociating it locally,
        /// no `willLogOut` event will be triggered.
        case willLogOut(_ details: AccountDetails)
        
        /// The account with the given details is being disassociated (e.g., because it was logged out or deleted).
        ///
        /// - Note: In previous releases of the package, this case was named `disassociatingAccount`.
        case didDisassociate(_ details: AccountDetails)
        
        /// The currently associated user account is about to be deleted.
        ///
        /// This event signals that the user requested to have their account deleted, and that the user's data is about to be deleted.
        ///
        /// - Note: Make sure to report this event before the account is deleted.
        ///     Deletion might be forwarded to an external ``AccountStorageProvider`` which might report an error if it fails to fully delete the associated user data.
        ///
        /// - Note: In previous releases of the package, this case was named `deletingAccount`.
        case willDelete(_ accountId: String)
    }

    @StandardActor private var standard: (any AccountNotifyConstraint)?

    @Dependency(ExternalAccountStorage.self)
    private var storage

    private let subscriptions = Mutex<[UUID: AsyncStream<Event>.Continuation]>([:])


    /// Subscribe to event notifications.
    ///
    /// Use the async stream to await all future events.
    ///
    /// - Note: In contrast to events delivered to ``AccountNotifyConstraint/handleAccountEvent(_:)``,
    ///     events emitted to this stream will not be awaited by the account service.
    public var events: AsyncStream<Event> {
        newSubscription()
    }


    /// Initialize the notifications subsystem.
    public init() {}


    /// Report an event to the account subsystem.
    ///
    /// This method is used by an ``AccountService`` to report an event.
    /// - Note: The ``Event/deletingAccount(_:)`` is the only event that an ``AccountService`` has to manually report to the Account module.
    /// - Parameter event: The event that occurred.
    @MainActor
    public func reportEvent(_ event: Event) async throws {
        await standard?.handleAccountEvent(event)
        switch event {
        case .willDelete(let accountId):
            try await storage.willDeleteAccount(for: accountId)
        case .didDisassociate(let details):
            await storage.userDidDisassociate(for: details.accountId)
        default:
            break
        }
        subscriptions.withLock {
            for sub in $0.values {
                sub.yield(event)
            }
        }
    }


    private func newSubscription() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            subscriptions.withLock {
                $0[id] = continuation
            }
            continuation.onTermination = { [weak self, id] _ in
                guard let self else {
                    return
                }
                subscriptions.withLock {
                    _ = $0.removeValue(forKey: id)
                }
            }
        }
    }
}

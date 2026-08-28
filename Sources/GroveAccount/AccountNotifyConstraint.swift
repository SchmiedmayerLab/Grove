//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Grove


/// A `Grove` Standard that allows to react to certain Account-based events.
///
/// Adopt this protocol in your Standard to respond to `Account` events.
///
/// ```swift
/// import Grove
/// import GroveAccount
///
/// actor MyStandard: Standard, AccountNotifyConstraint {
///     init() {}
///
///     func respondToEvent(_ event: AccountNotifications.Event) async {
///         switch event {
///         case .deletingAccount(let accountId):
///             // handle deletion of associated user data
///         }
///     }
/// }
/// ```
@available(iOS 18, macOS 15, watchOS 11, *)
public protocol AccountNotifyConstraint: Standard {
    /// Notifies the Standard that an event for the currently associated user occurred.
    ///
    /// For more information refer to ``AccountNotifications/Event``.
    func respondToEvent(_ event: AccountNotifications.Event) async
    
    /// Notifies the standard that the currently logged-in account is about to be logged out.
    ///
    /// - Note: This function will be folded into the ``AccountNotifications/Event`` enum in a future release.
    func willLogOut(_ details: AccountDetails) async

    /// Notifies the Standard that an awaited logout/account-removal transition failed after
    /// `willLogOut` returned and the existing account remains associated.
    func accountRemovalDidFail(_ details: AccountDetails) async
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension AccountNotifyConstraint {
    // swiftlint:disable:next missing_docs
    public func willLogOut(_ details: AccountDetails) async {}

    // swiftlint:disable:next missing_docs
    public func accountRemovalDidFail(_ details: AccountDetails) async {}
}

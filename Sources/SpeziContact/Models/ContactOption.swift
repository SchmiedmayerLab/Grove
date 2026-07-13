//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

private import MessageUI
import SwiftUI


/// Customizable way to get in contact with an individual and usually connected to a `Contact`.
///
/// The following example demonstrates the usage of the `ContactOption` within a `Contact`. For additional details, refer to the ``Contact`` documentation.
/// ```swift
/// Contact(
///     // other parameters for Contact
///     contactOptions: [
///         .call("+1 (123) 456-7890"),
///         .text("+1 (123) 456-7890"),
///         .email(addresses: ["email@address.com"]),
///         // Here is where the custom ContactOption can be used as a part of the contactOptions list
///         ContactOption(
///            image: Image(systemName: "safari.fill"),
///            title: "More Info",
///            action: {
///                // Action that should be performed on pressing this ContactOption (i.e. opening a link for a website)...
///             }
///         )
///     ]
/// )
/// ```
public struct ContactOption {
    let id = UUID()
    /// The image representing the `ContactOption` in the user interface.
    public let image: Image
    /// The title representing the `ContactOption` in the user interface.
    public let title: String
    /// The action that should be taken when a user chooses to use the `ContactOption`.
    public let action: @MainActor () -> Void

    
    /// Encodes a way to get in contact with an individual and usually connected to a `Contact`.
    /// - Parameters:
    ///   - image: The image representing the `ContactOption` in the user interface.
    ///   - title: The title representing the `ContactOption` in the user interface.
    ///   - action: The action that should be taken when a user chooses to use the `ContactOption`.
    public init(image: Image, title: String, action: @escaping @MainActor () -> Void) {
        self.image = image
        self.title = title
        self.action = action
    }
}


extension ContactOption {
    @MainActor private static var rootViewController: UIViewController? {
        UIApplication
            .shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
    }
    
    
    /// A ``ContactOption`` encoding a possibility to call an individual using a phone number.
    /// - Parameter number: The phone number to be called.
    public static func call(_ number: String) -> ContactOption {
        ContactOption(
            image: Image(systemName: "phone.fill"),
            title: String(localized: "Call", bundle: .module, comment: "Contact Option")
        ) {
            guard let url = URL(string: "tel://\(number)"), UIApplication.shared.canOpenURL(url) else {
                presentAlert(
                    title: String(localized: "Call", bundle: .module),
                    message: String(localized: "Call unavailable. You can manually reach out to \(number)", bundle: .module, comment: "Call unavailable. Manual approach.")
                )
                return
            }
            UIApplication.shared.open(url)
        }
    }
    
    /// A ``ContactOption`` encoding a possibility to text an individual using a phone numer.
    /// - Parameter number: The phone number to text to.
    public static func text(_ number: String) -> ContactOption {
        ContactOption(
            image: Image(systemName: "message.fill"),
            title: String(localized: "Text", bundle: .module, comment: "Contact Option")
        ) {
            guard let url = URL(string: "sms:\(number)"), UIApplication.shared.canOpenURL(url) else {
                presentAlert(
                    title: String(localized: "Text", bundle: .module),
                    message: String(localized: "Text unavailable. You can manually reach out to \(number)", bundle: .module, comment: "Text unavailable. Manual approach.")
                )
                return
            }
            UIApplication.shared.open(url)
        }
    }
    
    
    /// A ``ContactOption`` encoding a possibility to email an individual using a collection of email addresses.
    /// - Parameters:
    ///   - addresses: The email addresses to email to.
    ///   - subject: An optional subject line for the email.
    public static func email(addresses: [String], subject: String? = nil) -> ContactOption {
        ContactOption(
            image: Image(systemName: "envelope.fill"),
            title: String(localized: "Email", bundle: .module, comment: "Contact Option")
        ) {
            guard let subject = (subject ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "mailto:\(addresses.joined(separator: ";"))?subject=\(subject)"), UIApplication.shared.canOpenURL(url) else {
                presentAlert(
                    title: String(localized: "Email", bundle: .module),
                    message: String(
                        localized: "Email unavailable. You can manually reach out to \(addresses.joined(separator: ", "))",
                        bundle: .module,
                        comment: "Email unavailable. Manual approach."
                    )
                )
                return
            }
            UIApplication.shared.open(url)
        }
    }

    @MainActor
    private static func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Ok", bundle: .module, comment: "Dismiss alert"), style: .default))
        rootViewController?.present(alert, animated: true, completion: nil)
    }
}

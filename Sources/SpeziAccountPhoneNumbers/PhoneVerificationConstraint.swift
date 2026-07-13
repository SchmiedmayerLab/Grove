//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import PhoneNumberKit
import Spezi


/// A `Spezi` Standard that provides phone number verification functionality.
///
/// Adopt this protocol in your Standard to implement phone number verification services.
/// This protocol defines the interface for starting and completing phone verification processes.
///
/// - Note: The `number` parameter in both methods identifies the phone number being verified.
public protocol PhoneVerificationConstraint: Standard {
    /// Starts the phone verification process.
    /// - Parameter number: The phone number to verify.
    /// - Throws: An error if the verification process cannot be started.
    func startVerification(_ number: PhoneNumber) async throws

    /// Completes the phone verification process.
    /// - Parameters:
    ///   - number: The phone number being verified.
    ///   - code: The verification code to validate.
    /// - Throws: An error if the verification process cannot be completed.
    func completeVerification(_ number: PhoneNumber, _ code: String) async throws
    
    /// Deletes the phone number.
    /// - Parameter number: The phone number.
    /// - Throws: An error if the deletion cannot be completed.
    func delete(_ number: PhoneNumber) async throws
}

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order type_name

#if canImport(SwiftUI)
import SwiftUI


#if os(iOS) || os(visionOS) || os(tvOS)
typealias _ResponderBaseClass = UIResponder
typealias ApplicationDelegate = UIApplicationDelegate
#elseif os(macOS)
typealias _ResponderBaseClass = NSResponder
typealias ApplicationDelegate = NSApplicationDelegate
#elseif os(watchOS)
typealias _ResponderBaseClass = NSObject
typealias ApplicationDelegate = WKApplicationDelegate
#endif

#endif

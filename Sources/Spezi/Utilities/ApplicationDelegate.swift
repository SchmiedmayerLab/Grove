//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_types_order type_name missing_docs

#if canImport(SwiftUI)
import SwiftUI


#if os(iOS) || os(visionOS) || os(tvOS)
public typealias _ResponderBaseClass = UIResponder
public typealias ApplicationDelegate = UIApplicationDelegate
#elseif os(macOS)
public typealias _ResponderBaseClass = NSResponder
public typealias ApplicationDelegate = NSApplicationDelegate
#elseif os(watchOS)
public typealias _ResponderBaseClass = NSObject
public typealias ApplicationDelegate = WKApplicationDelegate
#endif

#endif

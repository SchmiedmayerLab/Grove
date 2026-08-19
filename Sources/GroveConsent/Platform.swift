//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(UIKit)
public import class UIKit.UIColor
public import class UIKit.UIFont
/// :nodoc:
@_documentation(visibility: internal)
public typealias UINSFont = UIFont
/// :nodoc:
@_documentation(visibility: internal)
public typealias UINSColor = UIFont
#elseif canImport(AppKit)
public import class AppKit.NSColor
public import class AppKit.NSFont
/// :nodoc:
@_documentation(visibility: internal)
public typealias UINSFont = NSFont
/// :nodoc:
@_documentation(visibility: internal)
public typealias UINSColor = NSColor
#endif

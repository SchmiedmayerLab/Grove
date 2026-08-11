//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation
import GroveLocalization
import ModelsR4


struct DiagnosticMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let message: String
    
    init(stringLiteral value: String) {
        message = value
    }
    
    @available(iOS 18, macOS 15, watchOS 11, *)
    init(_ title: String, @ArrayBuilder<Item> items: () -> [Item]) {
        message = {
            let items = items().compactMap { item -> (key: String, value: String)? in
                let desc = desc(item.value)
                return if desc == nil && item.omitIfNil {
                    nil
                } else {
                    (item.title, desc ?? "nil")
                }
            }
            guard !items.isEmpty else {
                return title
            }
            let maxItemTitleLength = items.lazy.map(\.key.count).max()! // swiftlint:disable:this force_unwrapping
            return items.reduce(into: title) { result, item in
                result.append("\n    - \(item.key):\(String(repeating: " ", count: maxItemTitleLength - item.key.count)) \(item.value)")
            }
        }()
    }
}


extension DiagnosticMessage {
    struct Item {
        let title: String
        let value: Any
        let omitIfNil: Bool
        init(_ title: String, omitIfNil: Bool = false, value: some Any) {
            self.title = title
            self.value = value
            self.omitIfNil = omitIfNil
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
private func desc(_ value: Any?) -> String? {
    switch value {
    case nil:
        nil
    case let value as any AnyOptional:
        desc(value.unwrappedOptional)
    case .some(let value as StudyBundle.LocalizedFileReference):
        value.filenameIncludingLocalization
    case .some(let value as StudyBundle.BundleValidationIssue.QuestionnaireIssue.Value):
        switch value {
        case .none:
            nil
        case let .some(_, value):
            desc(value)
        }
    case .some(let value as FHIRPrimitive<FHIRString>):
        if let value = value.value?.string {
            "'\(value)'"
        } else {
            nil
        }
    case .some(let value as URL):
        "'\(value.absoluteString.removingPercentEncoding ?? value.absoluteString)'"
    case .some(let value):
        String(describing: value)
    }
}

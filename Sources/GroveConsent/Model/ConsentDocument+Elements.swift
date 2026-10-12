//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveFoundation


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocument {
    typealias ToggleConfig = ConsentDocumentFormat.Toggle
    typealias SelectConfig = ConsentDocumentFormat.Selection

    enum Section: Hashable, Sendable {
        case markdown(String)
        case toggle(ToggleConfig)
        case select(SelectConfig)
        case signature(SignatureConfig)

        var isSignature: Bool {
            switch self {
            case .signature: true
            case .markdown, .toggle, .select: false
            }
        }
    }

    protocol InteractiveSectionProtocol: Hashable {
        associatedtype Value
        typealias StorageKeyPath = WritableKeyPath<UserResponses, [String: Value]>

        static var userResponsesKeyPath: StorageKeyPath { get }
        var id: String { get }
        var initialValue: Value { get }
        func valueMatchesExpected(_ value: Value) -> Bool
    }

    struct SignatureConfig: InteractiveSectionProtocol {
        typealias Value = ConsentDocument.SignatureStorage
        static var userResponsesKeyPath: StorageKeyPath { \.signatures }

        let id: String
        var initialValue: Value { .init(name: initialName) }
        var initialName: PersonNameComponents?

        func valueMatchesExpected(_ value: Value) -> Bool {
            value.didEnterNames && value.isSigned
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocumentFormat.Toggle: ConsentDocument.InteractiveSectionProtocol {
    typealias Value = Bool
    static var userResponsesKeyPath: StorageKeyPath { \.toggles }

    func valueMatchesExpected(_ value: Bool) -> Bool {
        expectedValue.map { value == $0 } ?? true
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocumentFormat.Selection: ConsentDocument.InteractiveSectionProtocol {
    typealias Value = String
    static var userResponsesKeyPath: StorageKeyPath { \.selects }

    static var emptySelectionDefaultTitle: String {
        String(localized: "CONSENT_NO_SELECTION_DEFAULT_TITLE", bundle: .module)
    }

    func valueMatchesExpected(_ value: String) -> Bool {
        guard value.isEmpty || options.contains(where: { $0.id == value }) else {
            return false
        }
        return switch expectedSelection {
        case .anything(let allowEmptySelection): allowEmptySelection || !value.isEmpty
        case .option(let id): value == id
        }
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension ConsentDocument.InteractiveSectionProtocol {
    var userResponsesKeyPath: WritableKeyPath<ConsentDocument.UserResponses, Value?> {
        Self.userResponsesKeyPath.appending(path: \.[id])
    }
}

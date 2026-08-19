//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GroveConsent
import GroveFoundation


enum ConsentDocumentIdentifier: Hashable, Identifiable, CaseIterable {
    case first
    case second
    case interactive
    
    var id: Self { self }
    
    fileprivate var filename: String {
        switch self {
        case .first:
            "Consent1"
        case .second:
            "Consent2"
        case .interactive:
            "Consent3"
        }
    }
    
    @MainActor var title: String {
        ConsentDocument.for(self).metadata.title ?? ""
    }
}


extension ConsentDocument {
    static func `for`(_ id: ConsentDocumentIdentifier) -> ConsentDocument {
        load(nameInBundle: id.filename)
    }
    
    private static func load(nameInBundle: String) -> ConsentDocument {
        guard let url = Bundle.main.url(forResource: nameInBundle, withExtension: "md") else {
            preconditionFailure("Unable to find URL for '\(nameInBundle)'")
        }
        do {
            return try ConsentDocument(contentsOf: url)
        } catch {
            fatalError("Unable to load ConsentDocument '\(nameInBundle)': \(error)")
        }
    }
}

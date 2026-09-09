//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// Controls extension appending.
public enum AppendExtensionBehaviour {
    /// Adding an extension does not affect existing extensions with the same URL.
    case additive
    /// Adding an extension removes every existing extension with the same URL first.
    case replace
}


// Appending lives here rather than in generated FHIR+ExtensionUtils.swift so regenerating the
// protocol conformances cannot remove the public helper API.
extension FHIRTypeWithExtensions {
    /// Appends an `Extension`.
    public mutating func append(extension: Extension, behaviour: AppendExtensionBehaviour = .additive) {
        append(extensions: CollectionOfOne(`extension`), behaviour: behaviour)
    }

    /// Appends multiple `Extension`s.
    public mutating func append(
        extensions: some Collection<Extension>,
        behaviour: AppendExtensionBehaviour = .additive
    ) {
        guard !extensions.isEmpty else {
            return
        }
        switch behaviour {
        case .additive:
            break
        case .replace:
            for element in extensions {
                removeAllExtensions(withUrl: element.url)
            }
        }
        var storage = `extension` ?? []
        storage.reserveCapacity(storage.count + extensions.count)
        storage.append(contentsOf: extensions)
        `extension` = storage
    }
}

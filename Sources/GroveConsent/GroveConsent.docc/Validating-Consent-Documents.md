# Validating and Extending Consent Documents

<!--
This source file is part of the Grove open-source project

SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
-->

Use the same typed control definitions when checking a document on a server and
presenting it in an app.

## Parse Once

```swift
import GroveConsent

let document = try ConsentDocumentFormat.decode(markdown)
for section in document.sections {
    switch section {
    case .toggle(let toggle):
        // Already checked: identity, Boolean attributes and label structure.
        print(toggle.id, toggle.initialValue)
    default:
        break
    }
}
```

``ConsentDocumentFormat/decode(_:additionalElements:)`` returns the original
Markdown structure and validated sections in document order. The built-in toggle,
selection, signature and option types validate their input during construction.
Document parsing checks unique control IDs; option IDs are unique within their
selection. Attribute values become typed values rather than being parsed again
by each consumer.

Use ``ConsentDocumentFormat/parse(_:additionalElements:)`` when only the
validated Markdown representation is needed.

This checks document structure, not study approval, participant identity or
completed responses. Applications must also enforce their renderer's Markdown
and asset policy. GroveConsent performs that check before presenting a document.

## Add a Platform-Specific Control

Implement ``ConsentDocumentElement`` and supply its type for each parse operation.
For example, a platform could define a rating control:

```swift
import Foundation
import GroveConsent
import GroveFoundation

struct StudyRating: ConsentDocumentElement {
    static let elementName = "rating"
    let id: String
    let maximum: Int

    init(parsing element: MarkdownDocument.CustomElement) throws {
        guard element.name == Self.elementName,
              element.attributes.allSatisfy({ ["id", "maximum"].contains($0.name) }),
              Set(element.attributes.map(\.name)).count == element.attributes.count,
              let id = element[attribute: "id"],
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let maximum = element[attribute: "maximum"].flatMap(Int.init), maximum > 0,
              element.content.isEmpty else {
            throw ConsentDocumentFormat.ValidationError.invalidControl(element.name)
        }
        self.id = id
        self.maximum = maximum
    }
}

let document = try ConsentDocumentFormat.decode(
    "<rating id=comfort maximum=5 />",
    additionalElements: [StudyRating.self]
)
```

The tag name routes input to the corresponding Swift initializer; callers register
types, not a second list of strings. The resulting `.custom` section retains the
typed value, which a platform can obtain with `as? StudyRating`.

Extensions are trusted application code, never loaded or selected from document
metadata. Registration is explicit and local to the call. Duplicate names and
replacement of built-ins are rejected. Custom controls share the document's ID
namespace and cannot change the identity parsed from their `id` attribute.

Each extension must validate its complete subtree and reject unsupported input.
Extensions are top-level controls; registering one does not permit it inside a
built-in toggle or selection. Unknown block-level tags are rejected, not silently
discarded.

Use the same extension types on every platform that publishes or consumes the
document. Registration only enables parsing: a platform must separately implement
presentation, response validation and export. GroveConsent's existing views and
PDF exporter support the built-ins, not arbitrary registered controls.

## Server Validation and PDF Export

GroveConsent builds on Linux. There, it provides the format, its typed definitions
and ``ConsentDocument`` without SwiftUI, PDFKit or PencilKit; its views and PDF export
are available only on Apple platforms.

GroveConsent's PDF exporter is an Apple-platform implementation. It uses PDFKit,
TPPDF and UIKit/AppKit drawing and font APIs; drawn signatures use PencilKit.
It does not run on Linux. A Linux exporter would need a separate rendering backend
and a portable signature representation, while reusing these validated definitions.
Neither structural validation nor a successful parse establishes PDF rendering support.

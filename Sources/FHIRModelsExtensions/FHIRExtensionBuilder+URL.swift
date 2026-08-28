//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import struct Foundation.URL
public import ModelsDSTU2
public import ModelsR4


/// Helper type for contructing and managing FHIR Extension URLs.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct FHIRExtensionURL: Sendable, Hashable {
    /// The underlying `URL`.
    public let url: URL

    /// The same identifier in string-backed form.
    public var canonicalURL: FHIRCanonicalURL {
        FHIRCanonicalURL(url.absoluteString)
    }

    /// Creates a FHIR Extension URL.
    public init(_ url: URL) {
        self.url = url
    }
    
    /// Creates a FHIR Extension URL from a String.
    ///
    /// - Important: The input String **must** be a valud `URL`; the initializer will otherwise crash the program.
    public init(_ url: String) {
        self.init(Self.parse(url))
    }

    public static func parse(_ url: String) -> URL {
        #if canImport(Darwin)
        return try! URL(url, strategy: .url) // swiftlint:disable:this force_try
        #else
        // https://github.com/swiftlang/swift-foundation/issues/1919
        return URL(string: url)! // swiftlint:disable:this force_unwrapping
        #endif
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionURL {
    /// R4 `FHIRPrimitive<FHIRURI>`
    public var r4: ModelsR4.FHIRPrimitive<ModelsR4.FHIRURI> { // swiftlint:disable:this identifier_name
        url.asFHIRURIPrimitive()
    }
    
    /// DSTU2 `FHIRPrimitive<FHIRURI>`
    public var dstu2: ModelsDSTU2.FHIRPrimitive<ModelsDSTU2.FHIRURI> {
        url.asFHIRURIPrimitive()
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension FHIRExtensionURL {
    /// Creates a new `FHIRExtensionURL` by appending a component.
    public func appending(component: some StringProtocol) -> Self {
        Self(url.appending(component: component))
    }
    
    /// Creates a new `FHIRExtensionURL>` by appending multiple components.
    public func appending(components: some Collection<some StringProtocol>) -> Self {
        func extend(_ url: URL) -> URL {
            components.reduce(url) { $0.appending(component: $1) }
        }
        return Self(extend(url))
    }
}


// MARK: FHIR Helpers

// swiftlint:disable discouraged_optional_collection

@available(iOS 18, macOS 15, watchOS 11, *)
extension ModelsR4.Extension {
    /// Creates an Extension from its parts, so a caller need not build one field at a time.
    public init(
        `extension`: [ModelsR4.Extension]? = nil,
        id: ModelsR4.FHIRPrimitive<ModelsR4.FHIRString>? = nil,
        url: FHIRExtensionURL,
        value: ModelsR4.Extension.ValueX? = nil
    ) {
        self.init(extension: `extension`, id: id, url: url.r4, value: value)
    }
}

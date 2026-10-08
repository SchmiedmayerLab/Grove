//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import ModelsR4


extension ExchangeGraph {
    /// The JSON view of one graph, parsed once and shared by every validation pass.
    ///
    /// The JSON checks were written against standalone encodes of each entry's resource. An entry's
    /// `resource` member of the encoded Bundle is that same encode, so the passes read it from here
    /// instead of each re-encoding and re-parsing every resource. An entry the parsed Bundle does not
    /// line up with falls back to the standalone encode, which is what every pass did before.
    final class ValidationDocument {
        private enum ResourceSource {
            case absent
            case parsed(Any)
            case standalone(ResourceProxy)
        }

        private let bundleJSON: Result<Any, any Error>
        private let resources: [ResourceSource]
        /// Each entry's resource as the model holds it.
        private let models: [ResourceProxy?]
        private var identifierCache: [Int: [Result<Identifier, any Error>]] = [:]
        private var typedIdentifierCache: [Int: Result<[RoledIdentifier], any Error>] = [:]

        /// - Parameters:
        ///   - bundle: The Bundle the passes validate.
        ///   - jsonData: The encoding of exactly `bundle`, when the caller already has it; `nil` encodes it here.
        convenience init(bundle: ModelsR4.Bundle, jsonData: Data?) {
            self.init(bundle: bundle, bundleJSON: Result {
                if let jsonData {
                    return try JSONSerialization.jsonObject(with: jsonData)
                }
                return try Self.tree(of: bundle)
            })
        }

        /// - Parameters:
        ///   - bundle: The Bundle the passes validate.
        ///   - tree: The JSON of exactly `bundle`, as ``WireJSONEncoder`` built it while encoding.
        convenience init(bundle: ModelsR4.Bundle, tree: Any) {
            self.init(bundle: bundle, bundleJSON: .success(tree))
        }

        private init(bundle: ModelsR4.Bundle, bundleJSON: Result<Any, any Error>) {
            let rawEntries = ((try? bundleJSON.get()) as? [String: Any])?["entry"] as? [Any]
            self.bundleJSON = bundleJSON
            self.models = (bundle.entry ?? []).map(\.resource)
            self.resources = (bundle.entry ?? []).enumerated().map { index, entry in
                guard let resource = entry.resource else {
                    return .absent
                }
                guard let rawEntries, rawEntries.indices.contains(index),
                      let object = (rawEntries[index] as? [String: Any])?["resource"] else {
                    return .standalone(resource)
                }
                return .parsed(object)
            }
        }

        /// The JSON of `value`: the tree ``WireJSONEncoder`` builds, whose native containers the passes read without
        /// bridging, or `JSONSerialization`'s parse of `JSONEncoder`'s bytes for a value it cannot encode.
        private static func tree(of value: some Encodable) throws -> Any {
            if let (_, tree) = try WireJSONEncoder.encodeKeepingTree(value) {
                return tree
            }
            return try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }

        /// The `identifier` array of the resource types a graph usually carries, as the model holds it; `nil` for any
        /// other type, whose identifiers are decoded from the JSON.
        private static func identifiers(of resource: ResourceProxy) -> [Identifier]? { // swiftlint:disable:this discouraged_optional_collection
            switch resource {
            case .observation(let resource): resource.identifier ?? []
            case .device(let resource): resource.identifier ?? []
            case .researchStudy(let resource): resource.identifier ?? []
            case .researchSubject(let resource): resource.identifier ?? []
            case .planDefinition(let resource): resource.identifier ?? []
            case .patient(let resource): resource.identifier ?? []
            case .provenance: []
            default: nil
            }
        }

        /// The parsed JSON of the whole Bundle.
        func bundleObject() throws -> Any {
            try bundleJSON.get()
        }

        /// The parsed JSON of the resource of the entry at `index` of `Bundle.entry`, or `nil` if it has none.
        func resourceObject(at index: Int) throws -> Any? {
            guard resources.indices.contains(index) else {
                return nil
            }
            switch resources[index] {
            case .absent:
                return nil
            case .parsed(let object):
                return object
            case .standalone(let resource):
                return try Self.tree(of: resource)
            }
        }

        /// Each element of the resource's `identifier` array, decoded as an Identifier, in order.
        ///
        /// A member that fails to decode keeps its error in place, so a pass that stops at an earlier
        /// member still reports what it reported before.
        func resourceIdentifiers(at index: Int) throws -> [Result<Identifier, any Error>] {
            if let cached = identifierCache[index] {
                return cached
            }
            let identifiers: [Result<Identifier, any Error>]
            if models.indices.contains(index), let model = models[index], let modelIdentifiers = Self.identifiers(of: model) {
                // The JSON is the model's own encoding, and an Identifier decodes from its encoding to itself.
                identifiers = modelIdentifiers.map { .success($0) }
            } else {
                identifiers = try decodedIdentifiers(at: index)
            }
            identifierCache[index] = identifiers
            return identifiers
        }

        /// Each element of the resource's JSON `identifier` array, decoded as an Identifier, in order.
        private func decodedIdentifiers(at index: Int) throws -> [Result<Identifier, any Error>] {
            let object = try resourceObject(at: index) as? [String: Any]
            let rawIdentifiers = object?["identifier"] as? [[String: Any]] ?? []
            return rawIdentifiers.map { rawIdentifier in
                Result<Identifier, any Error> {
                    try JSONDecoder().decode(Identifier.self, from: JSONSerialization.data(withJSONObject: rawIdentifier))
                }
            }
        }

        /// The identifiers of the entry's resource whose `Identifier.type` carries a Grove identifier role.
        ///
        /// A malformed Grove-typed identifier fails closed. Untyped business identifiers are not part
        /// of the exchange identity graph and are intentionally omitted.
        func typedResourceIdentifiers(at index: Int) throws -> [RoledIdentifier] {
            if let cached = typedIdentifierCache[index] {
                return try cached.get()
            }
            let result = Result<[RoledIdentifier], any Error> {
                var identifiers: [RoledIdentifier] = []
                for decoded in try resourceIdentifiers(at: index) {
                    let identifier = try decoded.get()
                    let carriesGroveRole = identifier.type?.coding?.contains {
                        $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
                    } == true
                    guard carriesGroveRole else {
                        continue
                    }
                    identifiers.append(try RoledIdentifier(identifier))
                }
                return identifiers
            }
            typedIdentifierCache[index] = result
            return try result.get()
        }
    }
}

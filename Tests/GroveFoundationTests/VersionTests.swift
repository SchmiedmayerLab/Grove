//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable identical_operands

import Foundation
@testable import GroveFoundation
import Testing


@Suite
struct VersionTests {
    @Test
    func parsing() throws {
        #expect(Version(1, 0, 0) == "1.0.0")
        #expect(Version(1, 1, 1) == "1.1.1")
        #expect(Version(1, 2, 3) == "1.2.3")
        #expect(Version(1, 2, 3) != "1.2.3-beta")
        #expect(Version(1, 2, 3) != "1.2.3-beta.1")
        #expect(Version(1, 2, 3, buildMetadata: ["abc"]) == "1.2.3")
        #expect(Version.init("a.b.c") == nil) // swiftlint:disable:this explicit_init
        #expect(Version.init("-1.2.3") == nil) // swiftlint:disable:this explicit_init
    }

    @Test("Parsing enforces every SemVer lexical boundary")
    func strictGrammar() {
        let valid = [
            "0.0.0",
            "1.0.0-0",
            "1.0.0-alpha-1",
            "1.0.0-alpha+build.001",
            "1.0.0+001"
        ]
        for value in valid {
            #expect(Version(value) != nil, "expected valid SemVer: \(value)")
        }

        let invalid = [
            "01.0.0", "1.01.0", "1.0.01",
            "1.0.0-01", "1.0.0-", "1.0.0-alpha..1",
            "1.0.0+", "1.0.0+build..1",
            "v1.0.0", "1.0", "1.0.0 ", "1.0.0-álpha"
        ]
        for value in invalid {
            #expect(Version(value) == nil, "expected invalid SemVer: \(value)")
        }
    }
    
    
    @Test
    func compare() throws {
        #expect(Version(1, 2, 3) == Version(1, 2, 3))
        #expect(Version(1, 2, 3) < Version(1, 2, 4))
        #expect(Version(1, 2, 3) < Version(1, 3, 3))
        #expect(Version(1, 2, 3) < Version(2, 2, 3))
        #expect(!(Version(2, 2, 3) < Version(2, 2, 3)))
        #expect(!(Version(2, 3, 3) < Version(2, 2, 3)))
        #expect(Version(2, 3, 3) > Version(2, 2, 3))
        #expect(Version(2, 3, 3) >= Version(2, 2, 3))
        
        #expect(Version(1, 0, 0) < Version(2, 0, 0))
        #expect(Version(2, 0, 0) < Version(2, 1, 0))
        #expect(Version(2, 1, 0) < Version(2, 1, 1))
        #expect(Version(1, 0, 1) > Version(1, 0, 0))
        #expect(!(Version(1, 0, 0) > Version(1, 0, 0)))
        #expect(Version(1, 0, 0) >= Version(1, 0, 0))
        #expect(Version(1, 0, 0) > Version(0, 0, 1))
        #expect(Version(0, 0, 1) < Version(1, 0, 0))
        #expect(Version(0, 1, 0) < Version(1, 0, 0))
        #expect(Version(0, 1, 1) < Version(1, 0, 0))
        #expect(Version(0, 0, 1) >= Version(0, 0, 1))
        #expect(Version(0, 0, 2) >= Version(0, 0, 1))
        #expect(Version(0, 1, 0) > Version(0, 0, 1))
        #expect(Version(0, 1, 0) >= Version(0, 0, 1))
        #expect(Version(3, 1, 0) > Version(2, 1, 1))
        #expect(Version(3, 1, 0) >= Version(2, 1, 1))
        #expect(Version(3, 1, 5) > Version(2, 1, 1))
        #expect(Version(3, 1, 5) >= Version(2, 1, 1))
        
        #expect(Version("1.0.0-alpha") < Version(1, 0, 0))
        
        #expect(Version("1.2.3-beta.1") < Version("1.2.3-beta.2"))
        #expect(Version("1.2.3-beta.1") < Version("1.2.3-beta.2+123"))
        #expect(Version("1.2.3-beta.1+123") < Version("1.2.3-beta.2"))
        #expect(Version("1.2.3-beta.1") == Version("1.2.3-beta.1"))
        #expect(Version("1.2.3-beta.3") > Version("1.2.3-beta.1"))
        #expect(Version("1.2.3-beta.3") > Version("1.2.3-alpha.3"))
        #expect(Version("1.2.3-alpha.1.2") == Version("1.2.3-alpha.1.2"))
        #expect(Version("1.2.3-beta.1.2") != Version("1.2.3-alpha.1.2"))
        #expect(Version("1.2.3-alpha.1.2") >= Version("1.2.3-alpha.1.2"))
        #expect(Version("1.2.3-alpha") < Version("1.2.3-alpha.1"))
        #expect(Version("1.2.3-alpha") < Version("1.2.3-alpha.1.2"))
        #expect(Version("1.2.3-alpha") > Version("1.2.3-1"))
        #expect(Version("1.2.3-alpha.1") < Version("1.2.3-alpha.a"))
        #expect(!(Version("1.2.3-alpha.a") < Version("1.2.3-alpha.1")))
    }

    @Test("Nonnumeric prerelease identifiers use antisymmetric ASCII SemVer ordering")
    func prereleaseASCIIOrdering() {
        let ordered: [Version] = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0"
        ]
        for lowerIndex in ordered.indices {
            for upperIndex in ordered.indices where lowerIndex < upperIndex {
                let lower = ordered[lowerIndex]
                let upper = ordered[upperIndex]
                #expect(lower < upper)
                #expect(!(upper < lower))
                #expect(lower != upper)
            }
        }
        #expect(Version("1.0.0-alpha") < Version("1.0.0-beta"))
        #expect(!(Version("1.0.0-beta") < Version("1.0.0-alpha")))
    }

    @Test("Build metadata-neutral equality has matching Hashable behavior")
    func buildMetadataHashing() {
        let versions: Set<Version> = ["1.2.3+one", "1.2.3+two", "1.2.3"]
        #expect(versions.count == 1)
    }
    
    
    @Test
    func coding() throws {
        let versions: [Version] = [
            "1.0.0",
            "1.1.1",
            "1.2.3",
            "1.2.3-beta",
            "1.2.3-beta.1",
            "1.2.3-alpha.1.2",
            "0.0.1-zlorb.12+1234"
        ]
        for version in versions {
            let encoded = try JSONEncoder().encode(version)
            let decoded = try JSONDecoder().decode(Version.self, from: encoded)
            #expect(decoded == version)
        }
        let invalidEncoding = try JSONEncoder().encode("1.2.-3")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Version.self, from: invalidEncoding)
        }
    }
}

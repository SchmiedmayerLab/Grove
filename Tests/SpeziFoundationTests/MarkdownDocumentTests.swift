//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// swiftlint:disable file_length

import Foundation
@testable import SpeziFoundation
import Testing


@Suite
struct MarkdownDocumentTests { // swiftlint:disable:this type_body_length
    @Test
    func parse() throws {
        let input = """
            # Hello World
            
            How are you doing?
            """
        let doc = try MarkdownDocument(processing: input)
        #expect(doc == MarkdownDocument(metadata: .init(), blocks: [
            .markdown(id: "hello-world", rawContents: "# Hello World\n\nHow are you doing?")
        ]))
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func metadata() throws {
        let input = """
            ---
            title: Document Title
            version: 1.0.0
            ---
            """
        let doc = try MarkdownDocument(processing: input)
        #expect(doc == MarkdownDocument(
            metadata: [
                "title": "Document Title",
                "version": "1.0.0"
            ],
            blocks: []
        ))
        #expect(doc.metadata.title == "Document Title")
        #expect(doc.metadata.version == Version(1, 0, 0))
        #expect(doc.metadata.mapIntoSet(\.key) == ["title", "version"])
    }

    @Test
    func metadataCoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let metadata: MarkdownDocument.Metadata = [
            "title": "Study Consent",
            "version": "1.0.0"
        ]
        let encoded = try encoder.encode(metadata)
        let decoded = try JSONDecoder().decode(MarkdownDocument.Metadata.self, from: encoded)
        #expect(decoded == metadata)
        
        let encoded2 = try encoder.encode([
            "title": "Study Consent",
            "version": "1.0.0"
        ])
        let decoded2 = try JSONDecoder().decode(MarkdownDocument.Metadata.self, from: encoded2)
        #expect(encoded2 == encoded)
        #expect(decoded2 == metadata)
    }
    
    @Test
    func simpleParsing() throws {
        let input = """
            # Hello World
            
            This is our study.
            
            We look forward to welcoming you into the fold.
            - we
            - look
            - forward
            - to welcoming you
            """
        let document = try MarkdownDocument(processing: input)
        #expect(document.metadata.isEmpty)
        #expect(document.blocks == [
            .markdown(id: "hello-world", rawContents: input)
        ])
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func frontmatterParsing() throws {
        let input = """
            ---
            title: abc
            version: 1.0.2
            keyOnlyEntry:
            keyAndValueEntry: value
            ---
            
            First markdown block
            - abc
            - def
            """
        let document = try MarkdownDocument(processing: input)
        #expect(document.metadata == [
            "title": "abc",
            "version": "1.0.2",
            "keyOnlyEntry": "",
            "keyAndValueEntry": "value"
        ])
        #expect(document.metadata.title == "abc")
        #expect(document.metadata.version == Version(1, 0, 2))
        #expect(document.blocks == [
            .markdown(id: nil, rawContents: "First markdown block\n- abc\n- def")
        ])
        #expect(try MarkdownDocument.Metadata(parsing: input) == document.metadata)
    }

    
    @Test
    func markdownSectionIds() throws {
        let input = """
            # First Heading
            ## Second Heading
            ### Third Heading
            #### Fourth Heading
            ##### Fifth Heading
            ###### Sixth Heading
            
            First Heading
            -------------
            
            Second Heading
            ==============
            
            """
        let doc = try MarkdownDocument(processing: input)
        #expect(doc == MarkdownDocument(
            metadata: .init(),
            blocks: [
                .markdown(id: "first-heading", rawContents: "# First Heading"),
                .markdown(id: "second-heading", rawContents: "## Second Heading"),
                .markdown(id: "third-heading", rawContents: "### Third Heading"),
                .markdown(id: "fourth-heading", rawContents: "#### Fourth Heading"),
                .markdown(id: "fifth-heading", rawContents: "##### Fifth Heading"),
                .markdown(id: "sixth-heading", rawContents: "###### Sixth Heading"),
                .markdown(id: "first-heading", rawContents: "First Heading\n-------------"),
                .markdown(id: "second-heading", rawContents: "Second Heading\n==============")
            ]
        ))
    }
    
    @Test
    func comments0() throws {
        let input = """
            # Hello World
            
            <!--How are you doing today?-->
            """
        let document = try MarkdownDocument(processing: input)
        #expect(document.blocks == [
            .markdown(id: "hello-world", rawContents: "# Hello World")
        ])
    }
    
    @Test
    func comments1() throws {
        let input = """
            # Hello World
            
            <!--<toggle id=t1>T1</>-->
            """
        let document = try MarkdownDocument(processing: input)
        #expect(document.blocks == [
            .markdown(id: "hello-world", rawContents: "# Hello World")
        ])
    }
    
    @Test
    func customElements() throws { // swiftlint:disable:this function_body_length
        let input = """
            # Hello World
            
            Welcome to our Study
            
            <toggle id=t1 initial-value=false expected-value=true>
                I'm fine with some of my health data being used for scientific research.
            </toggle>
            
            Selection block:
            
            <select id=s1 initial-value=o1 expected-value="*">
                Please select a value:
                <option id=o0>T0</option>
                <option id=o1>T1</option>
                Or maybe this one?
                <option id=o2>T2</option>
            </select>
            
            Please sign the form below:
            <signature id=sig />
            """
        let doc = try MarkdownDocument(processing: input, customElementNames: ["toggle", "select", "signature", "option"])
        #expect(doc == MarkdownDocument(
            metadata: .init(),
            blocks: [
                .markdown(id: "hello-world", rawContents: "# Hello World\n\nWelcome to our Study"),
                .customElement(.init(
                    name: "toggle",
                    attributes: [
                        .init(name: "id", value: "t1"),
                        .init(name: "initial-value", value: "false"),
                        .init(name: "expected-value", value: "true")
                    ],
                    content: [
                        .text("I'm fine with some of my health data being used for scientific research.")
                    ],
                    raw: """
                        <toggle id=t1 initial-value=false expected-value=true>
                            I'm fine with some of my health data being used for scientific research.
                        </toggle>
                        """
                )),
                .markdown(id: nil, rawContents: "Selection block:"),
                .customElement(.init(
                    name: "select",
                    attributes: [
                        .init(name: "id", value: "s1"),
                        .init(name: "initial-value", value: "o1"),
                        .init(name: "expected-value", value: "*")
                    ],
                    content: [
                        .text("Please select a value:"),
                        .element(.init(
                            name: "option",
                            attributes: [.init(name: "id", value: "o0")],
                            content: [.text("T0")],
                            raw: "<option id=o0>T0</option>"
                        )),
                        .element(.init(
                            name: "option",
                            attributes: [.init(name: "id", value: "o1")],
                            content: [.text("T1")],
                            raw: "<option id=o1>T1</option>"
                        )),
                        .text("Or maybe this one?"),
                        .element(.init(
                            name: "option",
                            attributes: [.init(name: "id", value: "o2")],
                            content: [.text("T2")],
                            raw: "<option id=o2>T2</option>"
                        ))
                    ],
                    raw: """
                        <select id=s1 initial-value=o1 expected-value="*">
                            Please select a value:
                            <option id=o0>T0</option>
                            <option id=o1>T1</option>
                            Or maybe this one?
                            <option id=o2>T2</option>
                        </select>
                        """
                )),
                .markdown(id: nil, rawContents: "Please sign the form below:"),
                .customElement(.init(
                    name: "signature",
                    attributes: [.init(name: "id", value: "sig")],
                    content: [],
                    raw: "<signature id=sig />"
                ))
            ]
        ))
        #expect(doc.blocks.map(\.id) == ["hello-world", "t1", nil, "s1", nil, "sig"])
        #expect(doc.blocks.map(\.isMarkdown) == [true, false, true, false, true, false])
        #expect(doc.blocks.map(\.isCustomElement) == [false, true, false, true, false, true])
    }
    
    @Test
    func customElements2() throws {
        let input = """
            # Spezi
            Hello World :)
            
            <toggle id=t1>T1</>
            <signature id=s1 />
            """
        let doc = try MarkdownDocument(processing: input, customElementNames: ["toggle"])
        #expect(doc == MarkdownDocument(
            metadata: .init(),
            blocks: [
                .markdown(id: "spezi", rawContents: "# Spezi\nHello World :)"),
                .customElement(.init(
                    name: "toggle",
                    attributes: [.init(name: "id", value: "t1")],
                    content: [.text("T1")],
                    raw: "<toggle id=t1>T1</>"
                )),
                .markdown(id: nil, rawContents: "<signature id=s1 />")
            ]
        ))
    }
    
    @Test
    func customElements3() throws {
        let input = """
            # Spezi
            Hello World :)
            
            <toggle id=t1>T1</>
            <signature id=s1 />
            """
        let doc = try MarkdownDocument(processing: input, customElementNames: ["signature"])
        #expect(doc == MarkdownDocument(
            metadata: .init(),
            blocks: [
                .markdown(id: "spezi", rawContents: "# Spezi\nHello World :)\n\n<toggle id=t1>T1</>"),
                .customElement(.init(
                    name: "signature",
                    attributes: [.init(name: "id", value: "s1")],
                    content: [],
                    raw: "<signature id=s1 />"
                ))
            ]
        ))
    }
    
    @Test(arguments: [
        "<signature id=sig></signature>",
        "<signature id=sig></>",
        "<signature id=sig />",
        "<signature id=sig/>"
    ])
    func endOfTagHandling(input: String) throws {
        let document = try MarkdownDocument(processing: input, customElementNames: ["signature"])
        #expect(document == .init(metadata: [:], blocks: [
            .customElement(.init(
                name: "signature",
                attributes: [.init(name: "id", value: "sig")],
                content: [],
                raw: input
            ))
        ]))
    }
    
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1, *)
    @Test
    func readFromFile() throws {
        let input = """
            ---
            title: Title
            ---
            
            # Hello World
            
            <toggle id=t1>T1</>
            """
        let data = try #require(input.data(using: .utf8))
        let dirUrl = URL.temporaryDirectory.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: dirUrl)
        }
        let url = dirUrl.appending(component: "doc.md")
        try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true)
        try data.write(to: url)
        let document = try MarkdownDocument(contentsOf: url, customElementNames: ["toggle"])
        #expect(document == MarkdownDocument(
            metadata: [
                "title": "Title"
            ],
            blocks: [
                .markdown(id: "hello-world", rawContents: "# Hello World"),
                .customElement(.init(
                    name: "toggle",
                    attributes: [.init(name: "id", value: "t1")],
                    content: [.text("T1")],
                    raw: "<toggle id=t1>T1</>"
                ))
            ],
            baseUrl: dirUrl
        ))
    }
    
    @Test
    func invalidFrontmatter0() throws {
        let input = """
            ---
            title: Title
            
            version: 1.0.0
            ---
            """
        let document = try MarkdownDocument(processing: input)
        #expect(document == .init(metadata: [
            "title": "Title",
            "version": "1.0.0"
        ], blocks: []))
    }
    
    @Test
    func invalidFrontmatter1() throws {
        let input = """
            ---
            title: Title
            version: 1.0.0
            """
        #expect(throws: (any Error).self) {
            try MarkdownDocument(processing: input)
        }
    }
    
    @Test
    func invalidFrontmatter2() throws {
        let input = """
            ---
            title: Title
            version:
            """
        #expect(throws: (any Error).self) {
            try MarkdownDocument(processing: input)
        }
    }
    
    @Test(arguments: [
        "<toggle id=></toggle>",
        "<toggle id=></>",
        "<toggle id=/>"
    ])
    func emptyAttrValue(input: String) throws {
        let document = try MarkdownDocument(processing: input, customElementNames: ["toggle"])
        #expect(document == .init(metadata: [:], blocks: [
            .customElement(.init(
                name: "toggle",
                attributes: [.init(name: "id", value: "")],
                content: [],
                raw: input
            ))
        ]))
    }
    
    @Test(arguments: [
        "<toggle id=-123></toggle>",
        "<toggle id=-123></>",
        "<toggle id=-123/>"
    ])
    func integerAttrValue(input: String) throws {
        let document = try MarkdownDocument(processing: input, customElementNames: ["toggle"])
        #expect(document == .init(metadata: [:], blocks: [
            .customElement(.init(
                name: "toggle",
                attributes: [.init(name: "id", value: "-123")],
                content: [],
                raw: input
            ))
        ]))
    }
    
    
    @Test
    func doccExample() throws {
        let input = """
            # Study Consent Form
            Welcome to our study. As part of your participation, you will need to fill out and sign this consent form.
            
            ## Your rights
            You have the right to revoke this consent at any time; if you wish to do so, contact us at studies@acme.org
            
            <signature id=sig />
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["signature"])
        let expected = MarkdownDocument(
            metadata: [:],
            blocks: [
                .markdown(
                    id: "study-consent-form",
                    rawContents: """
                        # Study Consent Form
                        Welcome to our study. As part of your participation, you will need to fill out and sign this consent form.
                        """
                ),
                .markdown(
                    id: "your-rights",
                    rawContents: """
                        ## Your rights
                        You have the right to revoke this consent at any time; if you wish to do so, contact us at studies@acme.org
                        """
                ),
                .customElement(
                    MarkdownDocument.CustomElement(
                        name: "signature",
                        attributes: [.init(name: "id", value: "sig")],
                        raw: "<signature id=sig />"
                    )
                )
            ]
        )
        #expect(document == expected)
    }
    
    @Test
    func hruleParsing() throws {
        let input = """
            ---
            title: Welcome to the Spezi Ecosystem
            date: 2025-06-22T14:41:16+02:00
            ---
            
            # Welcome to the Spezi Ecosystem
            This article aims to provide you with a broad overview of Spezi.
            
            <marquee filename="PM5544.png" period=5 />
            
            ## Our Modules
            Spezi is architected to be a highly modular system, allowing your application to ...
            
            ---
            
            ### SpeziHealthKit
            text text text
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["marquee"])
        #expect(document == MarkdownDocument(
            metadata: [
                "title": "Welcome to the Spezi Ecosystem",
                "date": "2025-06-22T14:41:16+02:00"
            ],
            blocks: [
                .markdown(
                    id: "welcome-to-the-spezi-ecosystem",
                    rawContents: "# Welcome to the Spezi Ecosystem\nThis article aims to provide you with a broad overview of Spezi."
                ),
                .customElement(.init(
                    name: "marquee",
                    attributes: [.init(name: "filename", value: "PM5544.png"), .init(name: "period", value: "5")],
                    content: [],
                    raw: #"<marquee filename="PM5544.png" period=5 />"#
                )),
                .markdown(
                    id: "our-modules",
                    rawContents: "## Our Modules\nSpezi is architected to be a highly modular system, allowing your application to ...\n\n---"
                ),
                .markdown(id: "spezihealthkit", rawContents: "### SpeziHealthKit\ntext text text")
            ]
        ))
    }
    
    @Test
    func attrValue0() throws {
        let input = """
            <elem id="hello world" />
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["elem"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(name: "elem", attributes: [.init(name: "id", value: "hello world")], content: [], raw: input))
        ]))
    }
    
    @Test(arguments: [
        #"<elem id=1234 />"#,
        #"<elem id="1234" />"#
    ])
    func attrValue1(input: String) throws {
        let document = try MarkdownDocument(processing: input, customElementNames: ["elem"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(name: "elem", attributes: [.init(name: "id", value: "1234")], content: [], raw: input))
        ]))
    }
    
    @Test
    func nonAsciiInput() throws {
        let input = """
            # Hello World 🏳️‍🌈👨‍🌾👨‍👩‍👦
            
            <elem id="👨‍🌾" />
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["elem"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .markdown(id: "hello-world", rawContents: "# Hello World 🏳️‍🌈👨‍🌾👨‍👩‍👦"),
            .customElement(.init(name: "elem", attributes: [.init(name: "id", value: "👨‍🌾")], content: [], raw: #"<elem id="👨‍🌾" />"#))
        ]))
    }
    
    @Test
    func textInCustomElement() throws {
        let input = """
            <custom>
            abc
            def
            
            ghi
            
            jkl
            mno
            </custom>
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["custom"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(
                name: "custom",
                attributes: [],
                content: [
                    .text("""
                        abc
                        def
                        
                        ghi
                        
                        jkl
                        mno
                        """)
                ],
                raw: input
            ))
        ]))
    }
    
    @Test
    func unexpectedHTML0() throws {
        let input = "<strong>Hello there</strong>"
        let document = try MarkdownDocument(processing: input)
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .markdown(id: nil, rawContents: input)
        ]))
    }
    
    @Test
    func unexpectedHTML1() throws {
        let input = """
            <custom>
            <strong>L2</strong>
            </custom>
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["custom"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(
                name: "custom",
                attributes: [],
                content: [
                    .text("<strong>L2</strong>")
                ],
                raw: input
            ))
        ]))
    }
    
    @Test
    func unexpectedHTML2() throws {
        let input = """
            <custom>
            L1
            <strong>L2</strong>
            L3
            </custom>
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["custom"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(
                name: "custom",
                attributes: [],
                content: [
                    .text("L1"),
                    .text("<strong>L2</strong>"),
                    .text("L3")
                ],
                raw: input
            ))
        ]))
    }
    
    @Test
    func unexpectedHTML2a() throws {
        let input = """
            <custom>
            L1<strong>L2</strong>L3
            </custom>
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["custom"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(
                name: "custom",
                attributes: [],
                content: [
                    .text("L1"),
                    .text("<strong>L2</strong>"),
                    .text("L3")
                ],
                raw: input
            ))
        ]))
    }
    
    // test parsing of an unexpected HTML element containing a nested element that is expected.
    @Test
    func unexpectedHtmlNestingExpectedHtml() throws {
        let input = """
            <a>
            <b>
            <c>abc</c>
            </b>
            </a>
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["a", "c"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(
                name: "a",
                attributes: [],
                content: [
                    .text("""
                        <b>
                        <c>abc</c>
                        </b>
                        """)
                ],
                raw: input
            ))
        ]))
    }
    
    @Test
    func unexpectedHTML3() throws {
        let input = """
            <select id=short-term-physical-activity-trial expected-value="*">
            Would you like to join the short term physical activity promoting trial?
            
            <strong>
            If you select yes, you will go straight from the baseline monitoring week into the randomized crossover trial.
            </strong>

            If you select no, you will still be able to use the base My Heart Counts application.
            <option id=short-term-physical-activity-trial-yes>Yes</option>
            <option id=short-term-physical-activity-trial-no>No</option>
            </select>
            """
        let document = try MarkdownDocument(processing: input, customElementNames: ["select", "option"])
        #expect(document == MarkdownDocument(metadata: [:], blocks: [
            .customElement(.init(
                name: "select",
                attributes: [
                    .init(name: "id", value: "short-term-physical-activity-trial"),
                    .init(name: "expected-value", value: "*")
                ],
                content: [
                    .text("Would you like to join the short term physical activity promoting trial?"),
                    .text("""
                        <strong>
                        If you select yes, you will go straight from the baseline monitoring week into the randomized crossover trial.
                        </strong>
                        """),
                    .text("If you select no, you will still be able to use the base My Heart Counts application."),
                    .element(.init(
                        name: "option",
                        attributes: [.init(name: "id", value: "short-term-physical-activity-trial-yes")],
                        content: [.text("Yes")],
                        raw: "<option id=short-term-physical-activity-trial-yes>Yes</option>"
                    )),
                    .element(.init(
                        name: "option",
                        attributes: [.init(name: "id", value: "short-term-physical-activity-trial-no")],
                        content: [.text("No")],
                        raw: "<option id=short-term-physical-activity-trial-no>No</option>"
                    ))
                ],
                raw: input
            ))
        ]))
    }
}

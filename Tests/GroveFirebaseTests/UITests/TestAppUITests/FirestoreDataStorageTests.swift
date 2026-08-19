//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// The `FirestoreDataStorageTests` require the Firebase Firestore Emulator to run at port 8080.
///
/// Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
/// Firebase Local Emulator Suite.
final class FirestoreDataStorageTests: XCTestCase {
    private struct FirestoreElement: Decodable, Equatable {
        let name: String
        let fields: [String: [String: String]]
        
        
        init(name: String, fields: [String: [String: String]]) {
            self.name = name
            self.fields = fields
        }
        
        init(id: String, content: String) {
            self.init(
                name: "projects/grovefirebaseuitests/databases/(default)/documents/Test/\(id)",
                fields: [
                    "id": [
                        "stringValue": id
                    ],
                    "content": [
                        "stringValue": content
                    ]
                ]
            )
        }
        
        
        subscript(dynamicMember member: String) -> [String: String] {
            fields[member, default: [:]]
        }
    }
    
    
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false

        try await Self.deleteAllDocuments()
        try await Self.waitForDocuments([])
    }


    @MainActor
    func testFirestoreAdditions() async throws {
        let app = XCUIApplication()
        try await openFirestoreDataStorage(in: app)

        try add(id: "Identifier1", content: "1")

        try await Self.waitForDocuments(
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )
    }

    @MainActor
    func testFirestoreMerge() async throws {
        let app = XCUIApplication()
        try await openFirestoreDataStorage(in: app)

        try merge(id: "Identifier1", content: "1")

        try await Self.waitForDocuments(
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )
    }

    @MainActor
    func testFirestoreUpdate() async throws {
        let app = XCUIApplication()
        try await openFirestoreDataStorage(in: app)

        try add(id: "Identifier1", content: "1")

        try await Self.waitForDocuments(
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )

        try add(id: "Identifier1", content: "2")

        try await Self.waitForDocuments(
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "2"
                )
            ]
        )
    }


    @MainActor
    func testFirestoreDelete() async throws {
        let app = XCUIApplication()
        try await openFirestoreDataStorage(in: app)

        try add(id: "Identifier1", content: "1")

        try await Self.waitForDocuments(
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )

        try remove(id: "Identifier1", content: "1")

        try await Self.waitForDocuments([])
    }


    @MainActor
    private func openFirestoreDataStorage(in app: XCUIApplication) async throws {
        XCTAssert(app.launchAndWait(for: app.buttons["FirestoreDataStorage"]), "The app did not come up.")
        app.buttons["FirestoreDataStorage"].tap()

        let documents = try await Self.getAllDocuments()
        XCTAssert(documents.isEmpty)
    }

    @MainActor
    private func add(id: String, content: String) throws {
        try enterFirestoreElement(id: id, content: content)
        tapAction("Upload Element")
    }

    @MainActor
    private func merge(id: String, content: String) throws {
        try enterFirestoreElement(id: id, content: content)
        tapAction("Merge Element")
    }

    @MainActor
    private func remove(id: String, content: String) throws {
        try enterFirestoreElement(id: id, content: content)
        tapAction("Delete Element")
    }

    @MainActor
    private func tapAction(_ title: String) {
        let button = XCUIApplication().buttons[title]
        // The action buttons stay disabled while a write is in flight, and taps that land in between are dropped silently.
        XCTAssert(button.waitUntilTappable(), "The \"\(title)\" button never became tappable.")
        button.tap()
    }

    @MainActor
    private func enterFirestoreElement(id: String, content: String) throws {
        let app = XCUIApplication()

        let identifierTextField = app.textFields["Enter the element's identifier."]
        XCTAssert(identifierTextField.wait(for: \.isHittable, toEqual: true, timeout: 10.0), "The Firestore test view did not appear.")
        try identifierTextField.delete(count: 42, options: .disableKeyboardDismiss)
        try identifierTextField.enter(value: id, options: .skipTextFieldSelection)

        let contentTextField = app.textFields["Enter the element's optional content."]
        try contentTextField.delete(count: 100, options: .disableKeyboardDismiss)
        try contentTextField.enter(value: content, options: .skipTextFieldSelection)
    }
}


extension FirestoreDataStorageTests {
    private static func deleteAllDocuments() async throws {
        let emulatorDocumentsURL = try XCTUnwrap(
            URL(string: "http://localhost:8080/emulator/v1/projects/grovefirebaseuitests/databases/(default)/documents")
        )
        var request = URLRequest(url: emulatorDocumentsURL)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirestoreDataStorageTests` require the Firebase Firestore Emulator to run at port 8080.
                
                Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }
    }

    private static func getAllDocuments() async throws -> [FirestoreElement] {
        let documentsURL = try XCTUnwrap(
            URL(string: "http://localhost:8080/v1/projects/grovefirebaseuitests/databases/(default)/documents/")
        )
        let (data, response) = try await URLSession.shared.data(from: documentsURL)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirestoreDataStorageTests` require the Firebase Firestore Emulator to run at port 8080.
                
                Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }

        struct ResponseWrapper: Decodable {
            let documents: [FirestoreElement]
        }

        do {
            return try JSONDecoder().decode(ResponseWrapper.self, from: data).documents
        } catch {
            return []
        }
    }

    /// Polls the emulator until it holds `expected` and asserts the result, so the tests observe the write instead of sleeping for it.
    private static func waitForDocuments(
        _ expected: [FirestoreElement],
        timeout: Duration = .seconds(10),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        var documents = try await getAllDocuments().sorted { $0.name < $1.name }

        while documents != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            documents = try await getAllDocuments().sorted { $0.name < $1.name }
        }

        XCTAssertEqual(documents, expected, file: file, line: line)
    }
}


extension XCUIElement {
    /// Waits until the element exists, is enabled, and is hittable.
    fileprivate func waitUntilTappable(timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND isEnabled == true AND isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

# ``XCTestApp``

<!--
                  
This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
             
-->

XCTestApp is a collection of types to run tests inside a test application.

Swift Packages tests cannot test user interface elements or iOS features that are only available when code runs in an application, e.g., HealthKit, the Secure Enclave, and more.
You can use XCTestApp in an app that tests framework functionality and verifies them using UI tests.

The framework has the following functionalities:


### TestAppTestCase

A ``TestAppTestCase`` is the base type that can be used to implement tests as part of a test application.

The following example demonstrates the usage of a combination of throwing and async test that use ``XCTAssert(_:message:file:line:)``, ``XCTAssertEqual(_:_:message:file:line:)``, ``XCTAssertNil(_:message:file:line:)``, and ``XCTUnwrap(_:message:file:line:)``
that are also included in the `XCTestApp` target.

```swift
struct ExampleTestCaseTest: TestAppTestCase {
    func runTests() async throws {
        try testAssert()
        try await testAssertEqual()
        try await testAssertNil()
        try testAssertUnwrap()
    }
    
    private func testAssert() throws {
        try XCTAssert(true)
        
        do {
            try XCTAssert(false)
            throw XCTestFailure(message: "Did not trigger the expected assertion.")
        } catch { }
    }
    
    private func testAssertEqual() async throws {
        try await Task.sleep(for: .seconds(0.1))
        
        
        try XCTAssertEqual(42, 42)
        
        do {
            try XCTAssertEqual(42, 43)
            throw XCTestFailure(message: "Did not trigger the expected assertion.")
        } catch { }
    }
    
    private func testAssertNil() async throws {
        try XCTAssertNil(Optional<Int>.none)
        
        do {
            try XCTAssertNil(42)
            throw XCTestFailure(message: "Did not trigger the expected assertion.")
        } catch { }
        
        
        try await Task.sleep(for: .seconds(0.1))
    }
    
    private func testAssertUnwrap() throws {
        print(try XCTUnwrap(42))
        
        do {
            _ = try XCTUnwrap(Optional<Int>.none)
            throw XCTestFailure(message: "Did not trigger the expected assertion.")
        } catch { }
    }
}
```


### TestAppView

You can use the ``TestAppView`` to automatically run a ``TestAppTestCase`` instance and display the result for a UI test to use:
```swift
struct ContentView: View {
    var body: some View {
        TestAppView(testCase: TestAppTestCaseTest())
    }
}
```

A UI test can then detect the passing state of the ``TestAppTestCase`` using a check of the existence of a static text:
```swift
class XCTestAppTests: XCTestCase {
    func testTestAppTestCaseTest() throws {
        let app = XCUIApplication()
        app.launch()
        
        XCTAssert(app.staticTexts["Passed"].waitForExistence(timeout: 5))
    }
}
```

### TestAppTests & TestAppTestsView

The ``TestAppTests`` protocol allows the definition of an enum of different test cases in your test application that are associated with SwiftUI views:
```swift
enum TestAppTestsExample: String, TestAppTests {
    case firstTest = "First Test"
    case secondTest = "Second Test"
    
    
    func view(withNavigationPath path: Binding<NavigationPath>) -> some View {
        switch self {
        case .firstTest:
            FirstTestTestsView()
        case .secondTest:
            SecondTestTestsView()
        }
    }
}
```

The ``TestAppTestsView`` can be subsequently used to display a `NavigationStack` and `List` containing all the test cases to simply navigate to each test case view:
```swift
@main
struct UITestsApp: App {
    var body: some Scene {
        WindowGroup {
            TestAppTestsView<TestAppTestsExample>()
        }
    }
}
```


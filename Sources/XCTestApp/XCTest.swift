//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// An error thrown in the XCT-based functions of the `XCTestExtensions` target.
public struct XCTestFailure: Error, CustomStringConvertible {
    let message: String
    let file: StaticString
    let line: UInt
    
    public var description: String {
        "XCTestFailure in \(file) at line \(line)\(message.isEmpty ? "" : ": \(message)")"
    }
    
    /// An error thrown in the XCT-based functions of the `XCTestExtensions` target.
    /// - Parameters:
    ///   - message: An optional description of a failure.
    ///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
    ///   - line: The line number where the failure occurs. The default is the line number where you call this function.
    public init(message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        self.message = message
        self.file = file
        self.line = line
    }
}


/// Asserts that an expression is true.
///
/// This function generates a failure when `expression == false`.
/// - Parameters:
///   - condition: An expression of Boolean type.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `expression == false`.
public func XCTAssert(
    _ condition: @autoclosure () throws -> Bool,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard try condition() else {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that an expression is true.
///
/// This function generates a failure when `expression == false`.
/// - Parameters:
///   - condition: An expression of Boolean type.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `expression == false`.
public func XCTAssertTrue(
    _ condition: @autoclosure () throws -> Bool,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard try condition() else {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that an expression is false.
///
/// This function generates a failure when `expression == true`.
/// - Parameters:
///   - condition: An expression of Boolean type.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `expression == false`.
public func XCTAssertFalse(
    _ condition: @autoclosure () throws -> Bool,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard try !condition() else {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that two values are equal.
///
/// Use this function to compare two non-optional values of the same type.
/// - Parameters:
///   - lhs: An expression of type `T`, where `T` is `Equatable`.
///   - rhs: A second expression of type `T`, where `T` is `Equatable`.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `lhs` and `rhs` are not equal.
public func XCTAssertEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard lhs == rhs else {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "'\(lhs)' is not equal to '\(rhs)'", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that two values are not equal.
///
/// Use this function to compare two non-optional values of the same type.
/// - Parameters:
///   - lhs: An expression of type `T`, where `T` is `Equatable`.
///   - rhs: A second expression of type `T`, where `T` is `Equatable`.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `lhs` and `rhs` are equal.
public func XCTAssertNotEqual<T: Equatable>(
    _ lhs: T,
    _ rhs: T,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard lhs != rhs else {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "'\(lhs)' is equal to '\(rhs)'", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that an expression is nil.
///
/// This function generates a failure when `expression != nil`.
/// - Parameters:
///   - expression: An expression to compare against `nil`.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `expression != nil`.
public func XCTAssertNil(
    _ expression: @autoclosure () throws -> (some Any)?,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if let value = try expression() {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "'\(value)'", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that an expression is not nil.
///
/// This function generates a failure when `expression == nil`.
/// - Parameters:
///   - expression: An expression to compare against `nil`.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `expression != nil`.
public func XCTAssertNotNil(
    _ expression: @autoclosure () throws -> (some Any)?,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    if try expression() == nil {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


/// Asserts that an expression is not `nil`, and returns the unwrapped value.
///
/// This function generates a failure when expression is `nil`. Otherwise, it returns the unwrapped value of expression for subsequent use in the test.
/// - Parameters:
///   - expression: An expression of type `T?`. The expression’s type determines the type of the return value.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when expression is not `nil`.
/// - Returns: The result of evaluating and unwrapping the expression, which is of type `T`. `XCTUnwrap()` only returns a value if expression is not `nil`.
public func XCTUnwrap<T>(
    _ expression: @autoclosure () throws -> T?,
    message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let unwrapped = try expression() else {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "Expected non-nil value of type '\(T.self)'", additionalMessage: message()),
            file: file,
            line: line
        )
    }
    return unwrapped
}


/// Asserts that an expression doesn’t throw an error.
///
/// This function generates a failure when the expression does throw an error.
/// - Parameters:
///   - expression: An expression that can throw an error.
///   - message: An optional description of a failure.
///   - file: The file where the failure occurs. The default is the filename of the test case where you call this function.
///   - line: The line number where the failure occurs. The default is the line number where you call this function.
/// - Throws: This function throws an ``XCTestFailure`` failure when `expression` throws an error.
public func XCTAssertNoThrow(
    _ expression: @autoclosure () throws -> some Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    do {
        _ = try expression()
    } catch {
        throw XCTestFailure(
            message: formatFailureMessage(baseText: "threw error '\(error)'", additionalMessage: message()),
            file: file,
            line: line
        )
    }
}


// MARK: Utilities

private func formatFailureMessage(
    _ caller: String = #function,
    baseText: String,
    additionalMessage: String
) -> String {
    let caller = caller.firstIndex(of: "(").map { caller[caller.startIndex..<$0] } ?? caller[...]
    var msg = "\(caller) failed"
    if !baseText.isEmpty {
        msg += ": \(baseText)"
    }
    if !additionalMessage.isEmpty {
        msg += " — \(additionalMessage)"
    }
    return msg
}

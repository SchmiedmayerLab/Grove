//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import GroveFoundation
import XCTest

#if canImport(ObjectiveC)

final class ExceptionHandlingTests: XCTestCase {
    func testNothingThrown() {
        do {
            let value = try catchingNSException {
                5
            }
            XCTAssertEqual(value, 5)
        } catch {
            XCTFail("Threw an error :/")
        }
    }
    
    func testNSExceptionThrown1() {
        // test that we can catch NSExceptions raised by Objective-C code.
        do {
            let _: Void = try catchingNSException {
                let string = "Hello there :)" as NSString
                _ = string.substring(with: NSRange(location: 12, length: 7))
            }
            XCTFail("Didn't throw an error :/")
        } catch {
            guard let error = error as? CaughtNSException else {
                XCTFail("Not a \(CaughtNSException.self)")
                return
            }
            XCTAssertEqual(error.exception.name, .invalidArgumentException)
            XCTAssertEqual(error.exception.reason, "-[__NSCFString substringWithRange:]: Range {12, 7} out of bounds; string length 14")
        }
    }
    
    func testNSExceptionThrown2() {
        // test that we can catch (custom) NSExceptions raised by Swift code.
        let exceptionName = NSExceptionName("CustomExceptionName")
        let exceptionReason = "There was a non-recoverable issue"
        do {
            let _: Void = try catchingNSException {
                NSException(name: exceptionName, reason: exceptionReason).raise()
                // unreachable, but the compiler doesn't know about this, because `-[NSException raise]` isn't annotated as being oneway...
                fatalError("unreachable")
            }
            XCTFail("Didn't throw an error :/")
        } catch {
            guard let error = error as? CaughtNSException else {
                XCTFail("Not a \(CaughtNSException.self)")
                return
            }
            XCTAssertEqual(error.exception.name, exceptionName)
            XCTAssertEqual(error.exception.reason, exceptionReason)
        }
    }
    
    func testSwiftErrorThrown() {
        // test that we can catch normal Swift errors.
        enum TestError: Error, Equatable {
            case abc
        }
        do {
            let _: Void = try catchingNSException {
                throw TestError.abc
            }
            XCTFail("Didn't throw an error :/")
        } catch {
            guard let error = error as? TestError else {
                XCTFail("Not a \(TestError.self)")
                return
            }
            XCTAssertEqual(error, TestError.abc)
        }
    }
}

#endif

//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@_spi(APISupport) @testable import GroveFoundation
import XCTest


final class SendableSharedRepositoryTests: XCTestCase {
    typealias Repository = SendableValueRepository<TestAnchor>

    private var repository = Repository()

    private var readRepository: Repository {
        repository // non-mutating access
    }

    @MainActor
    override func setUp() async throws {
        self.repository = .init()
        SharedRepositoryTests.computedValue = 3
        SharedRepositoryTests.optionalComputedValue = nil
    }

    func testIteration() {
        var repository = Repository()
        repository[TestStruct.self] = TestStruct(value: 3)

        for value in repository {
            XCTAssertTrue(value.anySource is TestStruct.Type)
            XCTAssertTrue(value.anyValue is TestStruct)
            XCTAssertEqual(value.anyValue as? TestStruct, TestStruct(value: 3))
        }
    }

    func testDefaultSubscript() throws {
        repository[TestStruct.self, default: TestStruct(value: 56)].value = 23

        let value = try XCTUnwrap(repository[TestStruct.self])
        XCTAssertEqual(value.value, 23)
    }

    func testSetAndGet() {
        // test basic insertion and retrieval
        let testStruct = TestStruct(value: 42)
        repository[TestStruct.self] = testStruct
        let contentOfStruct = readRepository[TestStruct.self]
        XCTAssertEqual(contentOfStruct, testStruct)

        // test overwrite and retrieval
        let newTestStruct = TestStruct(value: 24)
        repository[TestStruct.self] = newTestStruct
        let newContentOfStruct = readRepository[TestStruct.self]
        XCTAssertEqual(newContentOfStruct, newTestStruct)

        // test deletion
        repository[TestStruct.self] = nil
        let newerContentOfStruct = readRepository[TestStruct.self]
        XCTAssertNil(newerContentOfStruct)
    }

    func testGetWithDefault() {
        let testStruct = DefaultedTestStruct(value: 42)

        // test global default
        let defaultStruct = readRepository[DefaultedTestStruct.self]
        XCTAssertEqual(defaultStruct, DefaultedTestStruct(value: 0))

        // test that it falls back to the regular KnowledgeSource subscript if expecting a optional type
        let regularSubscript = readRepository[DefaultedTestStruct.self] ?? testStruct
        XCTAssertEqual(regularSubscript, testStruct)
    }

    func testContains() {
        let testStruct = TestStruct(value: 42)
        XCTAssertFalse(readRepository.contains(TestStruct.self))

        repository[TestStruct.self] = testStruct
        XCTAssertTrue(readRepository.contains(TestStruct.self))

        repository[TestStruct.self] = nil
        XCTAssertFalse(readRepository.contains(TestStruct.self))
    }

    func testGetAllThatConformTo() {
        let testStruct = TestStruct(value: 42)
        repository[TestStruct.self] = testStruct
        let testClass = TestClass(value: 42)
        repository[TestClass.self] = testClass

        let testTypes = readRepository.collect(allOf: (any TestTypes).self)
        XCTAssertEqual(testTypes.count, 2)
        XCTAssertTrue(testTypes.allSatisfy { $0.value == 42 })
    }

    func testMutationStruct() {
        let testStruct = TestStruct(value: 42)
        repository[TestStruct.self] = testStruct

        var contentOfStruct = readRepository[TestStruct.self]
        contentOfStruct?.value = 24
        XCTAssertEqual(testStruct.value, 42)
        XCTAssertEqual(contentOfStruct?.value, 24)
    }

    func testKeyLikeKnowledgeSource() {
        let testClass = TestClass(value: 42)
        repository[TestKeyLike.self] = testClass

        let contentOfClass = readRepository[TestKeyLike.self]
        XCTAssertEqual(contentOfClass, testClass)
    }

    @MainActor
    func testComputedKnowledgeSourceComputedOnlyPolicy() {
        let value = repository[ComputedTestStruct<_AlwaysComputePolicy, Repository>.self]
        let optionalValue = repository[OptionalComputedTestStruct<_AlwaysComputePolicy, Repository>.self]

        XCTAssertEqual(value, SharedRepositoryTests.computedValue)
        XCTAssertEqual(optionalValue, SharedRepositoryTests.optionalComputedValue)

        // make sure computed knowledge sources with `AlwaysCompute` policy are re-computed
        SharedRepositoryTests.computedValue = 5
        SharedRepositoryTests.optionalComputedValue = 4

        let newValue = repository[ComputedTestStruct<_AlwaysComputePolicy, Repository>.self]
        let newOptionalValue = repository[OptionalComputedTestStruct<_AlwaysComputePolicy, Repository>.self]

        XCTAssertEqual(newValue, SharedRepositoryTests.computedValue)
        XCTAssertEqual(newOptionalValue, SharedRepositoryTests.optionalComputedValue)
    }

    @MainActor
    func testComputedKnowledgeSourceComputedOnlyPolicyReadOnly() {
        let repository = repository // read-only

        let value = repository[ComputedTestStruct<_AlwaysComputePolicy, Repository>.self]
        let optionalValue = repository[OptionalComputedTestStruct<_AlwaysComputePolicy, Repository>.self]

        XCTAssertEqual(value, SharedRepositoryTests.computedValue)
        XCTAssertEqual(optionalValue, SharedRepositoryTests.optionalComputedValue)

        // make sure computed knowledge sources with `AlwaysCompute` policy are re-computed
        SharedRepositoryTests.computedValue = 5
        SharedRepositoryTests.optionalComputedValue = 4

        let newValue = repository[ComputedTestStruct<_AlwaysComputePolicy, Repository>.self]
        let newOptionalValue = repository[OptionalComputedTestStruct<_AlwaysComputePolicy, Repository>.self]

        XCTAssertEqual(newValue, SharedRepositoryTests.computedValue)
        XCTAssertEqual(newOptionalValue, SharedRepositoryTests.optionalComputedValue)
    }

    @MainActor
    func testComputedKnowledgeSourceStorePolicy() {
        let value = repository[ComputedTestStruct<_StoreComputePolicy, Repository>.self]
        let optionalValue = repository[OptionalComputedTestStruct<_StoreComputePolicy, Repository>.self]

        XCTAssertEqual(value, SharedRepositoryTests.computedValue)
        XCTAssertEqual(optionalValue, SharedRepositoryTests.optionalComputedValue)

        // get call bypasses the compute call, so tests if it's really stored
        let getValue = repository.get(ComputedTestStruct<_StoreComputePolicy, Repository>.self)
        let getOptionalValue = repository.get(OptionalComputedTestStruct<_StoreComputePolicy, Repository>.self)

        XCTAssertEqual(getValue, SharedRepositoryTests.computedValue)
        XCTAssertEqual(getOptionalValue, SharedRepositoryTests.optionalComputedValue) // this is nil

        // make sure computed knowledge sources with `Store` policy are not re-computed
        SharedRepositoryTests.computedValue = 5
        SharedRepositoryTests.optionalComputedValue = 4

        let newValue = repository[ComputedTestStruct<_StoreComputePolicy, Repository>.self]
        let newOptionalValue = repository[OptionalComputedTestStruct<_StoreComputePolicy, Repository>.self]

        XCTAssertEqual(newValue, value)
        XCTAssertEqual(newOptionalValue, SharedRepositoryTests.optionalComputedValue) // never stored as it was nil

        // last check if its really written now
        let writtenOptionalValue = repository.get(OptionalComputedTestStruct<_StoreComputePolicy, Repository>.self)
        XCTAssertEqual(writtenOptionalValue, SharedRepositoryTests.optionalComputedValue)

        // check again that it doesn't change
        SharedRepositoryTests.optionalComputedValue = nil
        XCTAssertEqual(repository[OptionalComputedTestStruct<_StoreComputePolicy, Repository>.self], 4)
    }

    @MainActor
    func testComputedKnowledgeSourcePreferred() {
        let value = repository[ComputedDefaultTestStruct<_StoreComputePolicy, Repository>.self]
        XCTAssertEqual(value, SharedRepositoryTests.computedValue)
    }
}

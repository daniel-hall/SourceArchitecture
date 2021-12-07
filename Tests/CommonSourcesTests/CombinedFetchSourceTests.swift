//
//  CombinedFetchedSourceTests.swift
//  SourceArchitecture
//
//  Copyright (c) 2021 Daniel Hall
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

@testable import SourceArchitecture
import Foundation
import XCTest


extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

final class CombinedFetchedSourceTests: XCTestCase {

    func testFetchedAndFetched() {
        let firstSource: MutableValueSource<Fetchable<String>> = .init(value: .fetching(.init(progress: nil)))
        let secondSource: MutableValueSource<Fetchable<String>> = .init(value: .fetching(.init(progress: nil)))
        let combined = firstSource.combinedFetch(with: secondSource)
        XCTAssertNotNil(combined.model.fetching)
        XCTAssertNil(combined.model.fetching?.progress)
        firstSource.setValue(.fetched(.init(value: "First", refresh: .noOp)))
        XCTAssertNotNil(combined.model.fetching)
        XCTAssertNil(combined.model.fetching?.progress)
        secondSource.setValue(.fetched(.init(value: "Second", refresh: .noOp)))
        XCTAssert((combined.model.fetched?.value.0, combined.model.fetched?.value.1) == ("First", "Second"))
    }

    func testFetchedAndFailure() {
        let firstSource: MutableValueSource<Fetchable<String>> = .init(value: .fetching(.init(progress: nil)))
        let secondSource: MutableValueSource<Fetchable<String>> = .init(value: .fetching(.init(progress: nil)))
        let combined = firstSource.combinedFetch(with: secondSource)
        firstSource.setValue(.fetched(.init(value: "First", refresh: .noOp)))
        secondSource.setValue(.failure(.init(error: "second error", failedAttempts: 1, retry: .noOp)))
        XCTAssertEqual(combined.model.failure?.error.localizedDescription, "second error")
    }

    // If there are two errors, the first one should be the one that bubbles up
    func testTwoFailures() {
        let firstSource: MutableValueSource<Fetchable<String>> = .init(value: .fetching(.init(progress: nil)))
        let secondSource: MutableValueSource<Fetchable<String>> = .init(value: .fetching(.init(progress: nil)))
        let combined = firstSource.combinedFetch(with: secondSource)
        firstSource.setValue(.failure(.init(error: "first error", failedAttempts: 1, retry: .noOp)))
        XCTAssertEqual(combined.model.failure?.error.localizedDescription, "first error")
        secondSource.setValue(.failure(.init(error: "second error", failedAttempts: 1, retry: .noOp)))
        XCTAssertEqual(combined.model.failure?.error.localizedDescription, "first error")
    }

    func testRefresh() {
        let firstExpectation = expectation(description: "first refresh")
        var firstHasRefreshed = false
        var firstSource: MutableValueSource<Fetchable<String>>!
        let firstRefresh = Action<Void>(identifier: "refresh") {
            firstHasRefreshed = true
            DispatchQueue.global().async {
                firstSource.setValue(.fetched(.init(value: "First2", refresh: .noOp)))
                firstExpectation.fulfill()
            }
        }
        firstSource = .init(value: .fetched(.init(value: "First", refresh: firstRefresh)))

        let secondExpectation = expectation(description: "second refresh")
        var secondHasRefreshed = false
        var secondSource: MutableValueSource<Fetchable<String>>!
        let secondRefresh = Action<Void>(identifier: "refresh") {
            secondHasRefreshed = true
            DispatchQueue.global().async {
                secondSource.setValue(.fetched(.init(value: "Second2", refresh: .noOp)))
                secondExpectation.fulfill()
            }
        }
        secondSource = .init(value: .fetched(.init(value: "Second", refresh: secondRefresh)))

        let combined = firstSource.combinedFetch(with: secondSource)

        let subscription = combined.subscribeTestClosure { [weak combined] in
            // Assert that we never reach a .failure or .fetching state in this test case
            switch combined?.model {
            case .fetching: XCTFail("Shouldn't ever reach fetching state")
            case .failure: XCTFail("Shouldn't ever read failure state")
            default: break
            }
        }

        XCTAssert(combined.model.fetched!.value == ("First", "Second"))
        try? combined.model.fetched?.refresh()
        // Validate that refresh was called on both sources
        XCTAssert((firstHasRefreshed, secondHasRefreshed) == (true, true))
        // Validate that was are still in a "fetched" state (since refresh shouldn't cause a state change to "fetching" and that we still have the original fetched values (new ones haven't been set yet)
        XCTAssert(combined.model.fetched!.value == ("First", "Second"))
        waitForExpectations(timeout: 1, handler: nil)
        // Now validate that we have the new values and are in a fetched state with them
        XCTAssert(combined.model.fetched!.value == ("First2", "Second2"))
        withExtendedLifetime(subscription) { }
    }
}

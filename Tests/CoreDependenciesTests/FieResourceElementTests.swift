//
//  FileResourceElementTests.swift
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

import Foundation
import XCTest
@testable import SourceArchitecture


final class FileResourceElementTests: XCTestCase {
    struct TestFileResource: FileResource {
        typealias Value = [String]
        var filePath: String { "test" }
    }
    
    struct TestFileResourceElement: ResourceElement {
        typealias Value = String
        let elementIdentifier: String
        let parentResource = TestFileResource()
        
        func set(element: String?) -> ([String]?) throws -> [String] {
            if let string = element {
                guard string == elementIdentifier else { return { $0 ?? [] } }
                return {
                    let existing = $0 ?? []
                    return existing.contains(string) ? existing : existing + [string]
                }
            } else {
                return {
                    var existing = $0 ?? []
                    existing.removeAll { $0 == elementIdentifier }
                    return existing
                }
            }
        }
        
        func getElement(from value: [String]) throws -> String? {
            value.first { $0 == elementIdentifier }
        }
    }
    
    func testFileElementSourceUpdatesFileSource() {
        let dependencies = CoreDependencies()
        let fileSource = dependencies.fileResource(TestFileResource())
        try? fileSource.model.set(["Foo", "Bar"])
        let fileElementSource = dependencies.fileResourceElement(TestFileResourceElement(elementIdentifier: "Foo"))
        XCTAssertEqual(fileElementSource.model.found?.value, "Foo")
        try? fileElementSource.model.clear?()
        XCTAssertEqual(fileSource.model.found?.value, ["Bar"])
    }
    
    func testFileElementSourceUpdateUpdatesFileSourceSubscribers() {
        let dependencies = CoreDependencies()
        let fileSource = dependencies.fileResource(TestFileResource())
        try? fileSource.model.set(["Foo", "Bar"])
        let fileElementSource = dependencies.fileResourceElement(TestFileResourceElement(elementIdentifier: "Foo"))
        let fileUpdateExpectation = expectation(description: "file updated")
        let subscription = fileSource.subscribeTestClosure {
            fileUpdateExpectation.fulfill()
        }
        try? fileElementSource.model.clear?()
        waitForExpectations(timeout: 1, handler: nil)
        withExtendedLifetime(subscription, {_ in })
    }
}

//
//  SyncedSourceTests.swift
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


private enum SyncedModel {
    case one(One)
    case two(Two)
    
    struct One {
        let title: String
        let switchToTwo: Action<Void>
    }
    
    struct Two {
        let title: String
        let switchToOne: Action<Void>
    }
    
    var title: String {
        switch self {
        case .one(let one): return one.title
        case .two(let two): return two.title
        }
    }
}

private final class TestSyncedSource: SyncedSource<SyncedModel>, ActionSource, CacheResource {
    struct Actions: ActionMethods {
        var switchToOne = ActionMethod(TestSyncedSource.switchToOne)
        var switchToTwo = ActionMethod(TestSyncedSource.switchToTwo)
    }
    struct MutableProperties: SyncedSourcePropertiesProvider {
        var syncProperties = SyncedSourceProperties()
    }
    private let state: MutableState<MutableProperties>
    let cacheIdentifier = "SyncedModel"
    init(dependencies: CacheDependency) {
        state = .init(mutableProperties: .init()) { state in .one(.init(title: "One", switchToTwo: state.switchToTwo)) }
        super.init(state, dependencies: dependencies)
    }
    private func switchToOne() {
        state.setModel(.one(.init(title: "One", switchToTwo: state.switchToTwo)))
    }
    private func switchToTwo() {
        state.setModel(.two(.init(title: "Two", switchToOne: state.switchToOne)))
    }
}


final class SyncedSourceTests: XCTestCase {
    
    func testSyncAtInit() throws {
        let dependencies = CoreDependencies()
        let first = TestSyncedSource(dependencies: dependencies)
        guard case .one(let one) = first.model else {
            throw "Expected to have an initial model value of .one"
        }
        try? one.switchToTwo()
        guard case .two = first.model else {
            throw "First test source didn't change to expected model state"
        }
        let second = TestSyncedSource(dependencies: dependencies)
        guard case .two = second.model else {
            throw "New instance of TestSyncedSource wasn't in sync"
        }
    }
    
    func testSyncAfterInit() throws {
        let dependencies = CoreDependencies()
        let first = TestSyncedSource(dependencies: dependencies)
        let second = TestSyncedSource(dependencies: dependencies)
        // Make sure they are starting synced
        XCTAssertEqual(first.model.title, second.model.title)
        // Now change the first source to second model case
        guard case .one(let one) = first.model else {
            throw "Source was expected to have model case .one"
        }
        try? one.switchToTwo()
        // Make sure both sources are now synced on the second state
        XCTAssertEqual(first.model.title, second.model.title)
        // Now change the second source back to the first model case
        guard case .two(let two) = second.model else {
            throw "Source was expected to have model case .two"
        }
        try? two.switchToOne()
        // Make sure both sources are now synced again on the first state
        XCTAssert((first.model.title, second.model.title) == ("One", "One"))
    }
}


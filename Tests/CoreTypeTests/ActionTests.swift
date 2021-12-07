//
//  ActionTests.swift
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

import XCTest
@testable import SourceArchitecture


final class ActionTests: XCTestCase {
    
    func testExpiredAction() throws {
        final class TestSource: Source<TestSource.Model>, ActionSource {
            enum Model {
                case firstState(FirstState)
                case secondState(SecondState)
                
                struct FirstState {
                    let state: String
                    let switchToSecond: Action<Void>
                }
                
                struct SecondState {
                    let state: String
                    let switchToFirst: Action<Void>
                }
            }
            struct Actions: ActionMethods {
                var switchToFirst = ActionMethod(TestSource.switchToFirst)
                var switchToSecond = ActionMethod(TestSource.switchToSecond)
            }
            let state: State
            init() {
                state = .init { state in .firstState(.init(state: "First", switchToSecond: state.switchToSecond))}
                super.init(state)
            }
            
            func switchToFirst() {
                state.setModel(.firstState(.init(state: "First", switchToSecond: state.switchToSecond)))
            }
            
            func switchToSecond() {
                state.setModel(.secondState(.init(state: "Second", switchToFirst: state.switchToFirst)))
            }
        }
        
        let testSource = TestSource()
        
        
        // Validate the the test source is starting in the expected first state (and save / bind a copy of its first model state)
        guard case .firstState(let firstState) = testSource.model else {
            throw "TestSource in unexpected state"
        }
        // Switch to the second state
        try? firstState.switchToSecond()
        // Validate that the switch worked and the model is now in its second state
        guard case .secondState = testSource.model else {
            throw "TestSource was expected to be in the second state"
        }
        // Now try to call the switch Action from the first state again even though we are now in the second state
        XCTAssertThrowsError(try firstState.switchToSecond())
    }
}

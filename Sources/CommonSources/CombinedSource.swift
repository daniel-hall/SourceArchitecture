//
//  CombinedSource.swift
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


/// Combines the latest value from two Sources into a single tuple value each time each Source updates
class CombinedSource<First, Second>: Source<(First, Second)> {
    private let first: Source<First>
    private let second: Source<Second>
    private let state: State
    init(firstSource: Source<First>, secondSource: Source<Second>) {
        self.first = firstSource
        self.second = secondSource
        let state = State(model: (firstSource.model, secondSource.model))
        self.state = state
        super.init(state)
        firstSource.subscribe(self, method: CombinedSource.update)
        secondSource.subscribe(self, method: CombinedSource.update)
    }
    
    private func update() {
        state.setModel((first.model, second.model))
    }
}


public extension Source {
    func combined<T>(with source: Source<T>) -> Source<(Model, T)> {
        CombinedSource(firstSource: self, secondSource: source)
    }
}

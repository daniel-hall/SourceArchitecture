//
//  MergedSource.swift
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


/// A Source that publishes updates from two other Sources that have the same Model and whose current model is the most recent update from the other two.
final class MergedSource<Model>: Source<Model> {
    private let first: Source<Model>
    private let second: Source<Model>
    private let state: State
    init(first: Source<Model>, second: Source<Model>) {
        self.first = first
        self.second = second
        self.state = .init(model: first.model)
        super.init(state)
        second.subscribe(self, method: MergedSource.updateSecond)
        first.subscribe(self, method: MergedSource.updateFirst)
    }
    
    private func updateFirst() {
        state.setModel(first.model)
    }
    
    private func updateSecond() {
        state.setModel(second.model)
    }
}

public extension Source {
    func merge(with source: Source<Model>) -> Source<Model> {
        MergedSource(first: self, second: source)
    }
}

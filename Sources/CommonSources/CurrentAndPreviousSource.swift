//
//  CurrentAndPreviousSource.swift
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


/// Publishes a CurrentAndPrevious value for any input Source
final class CurrentAndPreviousSource<T>: Source<CurrentAndPrevious<T>> {
    
    private struct MutableProperties {
        var previous: T?
    }
    private let input: Source<T>
    private let state: MutableState<MutableProperties>
    init(input: Source<T>) {
        self.input = input
        self.state = .init(mutableProperties: .init(), model: .init(current: input.model, previous: nil))
        super.init(state)
        input.subscribe(self, method: CurrentAndPreviousSource.update)
    }
    private func update() {
        state.setModel(.init(current: input.model, previous: state.previous))
        state.previous = input.model
    }
}

public extension Source {
    func currentAndPrevious() -> Source<CurrentAndPrevious<Model>> {
        CurrentAndPreviousSource(input: self)
    }
}

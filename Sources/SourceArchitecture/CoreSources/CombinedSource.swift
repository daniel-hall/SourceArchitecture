//
//  CombinedSource.swift
//  SourceArchitecture
//
//  Copyright (c) 2022 Daniel Hall
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
private final class CombinedSource<First, Second>: SourceOf<(First, Second)> {

    @Source var first: First
    @Source var second: Second

    lazy var initialModel: (First, Second) = {
        _first.subscribe(self, method: CombinedSource.updateFirst)
        _second.subscribe(self, method: CombinedSource.updateSecond)
        return model
    }()

    init(first: Source<First>, second: Source<Second>) {
        _first = first
        _second = second
    }

    func updateFirst(first: First) {
        model = (first, second)
    }

    func updateSecond(second: Second) {
        model = (first, second)
    }
}

public extension Source {
    func combined<T>(with source: Source<T>) -> Source<(Model, T)> {
        CombinedSource(first: self, second: source).eraseToSource()
    }
}

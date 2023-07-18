//
//  SourceArchitecture
//
//  Copyright (c) 2023 Daniel Hall
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
private final class CombinedSource<First, Second>: Source<(First, Second)> {

    @Sourced var first: First
    @Sourced var second: Second

    lazy var initialState: (First, Second) = {
        updateFirst(first: first)
        updateSecond(second: second)
        return state
    }()

    init(first: AnySource<First>, second: AnySource<Second>) {
        _first = .init(from: first, updating: CombinedSource.updateFirst)
        _second = .init(from: second, updating: CombinedSource.updateSecond)
    }

    func updateFirst(first: First) {
        state = (first, second)
    }

    func updateSecond(second: Second) {
        state = (first, second)
    }
}

public extension AnySource {
    func combined<T>(with source: AnySource<T>) -> AnySource<(Model, T)> {
        CombinedSource(first: self, second: source).eraseToAnySource()
    }
}

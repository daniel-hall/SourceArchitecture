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


/// A Source that filters upstream values using the provided closure.
private final class FilteredSource<Model>: Source<Model> {

    @Sourced var input: Model

    let shouldInclude: (Model) -> Bool

    lazy var initialState: Model = input

    init(inputSource: AnySource<Model>, shouldInclude: @escaping (Model) -> Bool) {
        _input = .init(from: inputSource, updating: FilteredSource.update)
        self.shouldInclude = shouldInclude
    }
    
    func update(value: Model) {
        if shouldInclude(value) {
            state = value
        }
    }
}

public extension AnySource {
    func filtering(using shouldInclude: @escaping (Model) -> Bool) -> AnySource<Model> {
        FilteredSource(inputSource: self, shouldInclude: shouldInclude).eraseToAnySource()
    }
}

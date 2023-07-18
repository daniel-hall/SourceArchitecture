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


/// A Source that will not publish an update if the new value is the same as the last value (based on the provided closure to check equality)
private final class FilteredDuplicatesSource<Model>: Source<Model> {

    @Sourced var input: CurrentAndPrevious<Model>

    let isDuplicate: (Model, Model) -> Bool

    lazy var initialState = input.current

    init(input: AnySource<Model>, isDuplicate: @escaping (Model, Model) -> Bool) {
        _input = .init(from: input.currentAndPrevious(), updating: FilteredDuplicatesSource.update)
        self.isDuplicate = isDuplicate
    }

    func update(value: CurrentAndPrevious<Model>) {
        if let previous = value.previous {
            if !isDuplicate(previous, value.current) {
                state = value.current
            }
        } else {
            state = value.current
        }
    }
}

public extension AnySource where Model: Equatable {
    /// Returns a Source which filters all duplicate values from this Source and publishes all non-duplicate values
    func filteringDuplicates() -> AnySource<Model> {
        FilteredDuplicatesSource(input: self, isDuplicate: { $0 == $1 } ).eraseToAnySource()
    }
}

public extension AnySource {
    /// Returns a Source which filters all duplicate values from this Source using the provided `isDuplicate` function and publishes all non-duplicate values
    func filteringDuplicates(using isDuplicate: @escaping (Model, Model) -> Bool) -> AnySource<Model> {
        FilteredDuplicatesSource(input: self, isDuplicate: isDuplicate).eraseToAnySource()
    }
}

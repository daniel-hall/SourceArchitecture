//
//  FilteredDuplicatesSource.swift
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


/// A Source that will not publish an update if the new value is the same as the last value (based on the provided closure to check equality)
private final class FilteredDuplicatesSource<Model>: SourceOf<Model> {

    @Source var input: CurrentAndPrevious<Model>

    let isDuplicate: (Model, Model) -> Bool

    lazy var initialModel = {
        _input.subscribe(self, method: FilteredDuplicatesSource.update, sendInitialModel: false)
        return input.current
    }()

    init(input: Source<Model>, isDuplicate: @escaping (Model, Model) -> Bool) {
        _input = input.currentAndPrevious()
        self.isDuplicate = isDuplicate
    }

    func update(value: CurrentAndPrevious<Model>) {
        if let previous = value.previous {
            if !isDuplicate(previous, value.current) {
                model = value.current
            }
        } else {
            model = value.current
        }
    }
}

public extension Source where Model: Equatable {
    /// Returns a Source which filters all duplicate values from this Source and publishes all non-duplicate values
    func filteringDuplicates() -> Source<Model> {
        FilteredDuplicatesSource(input: self, isDuplicate: { $0 == $1 } ).eraseToSource()
    }
}

public extension Source {
    /// Returns a Source which filters all duplicate values from this Source using the provided `isDuplicate` function and publishes all non-duplicate values
    func filteringDuplicates(using isDuplicate: @escaping (Model, Model) -> Bool) -> Source<Model> {
        FilteredDuplicatesSource(input: self, isDuplicate: isDuplicate).eraseToSource()
    }
}

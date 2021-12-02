//
//  FilteredDuplicatesSource.swift
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


/// A Source that will not publish an update if the new value is the same as the last value (based on the provided closure to check equality)
final class FilteredDuplicatesSource<Model>: Source<Model> {
    private let input: Source<CurrentAndPrevious<Model>>
    private let isDuplicate: (Model, Model) -> Bool
    private let state: State
    
    public init(inputSource: Source<Model>, isDuplicate: @escaping (Model, Model) -> Bool) {
        self.input = inputSource.currentAndPrevious()
        self.isDuplicate = isDuplicate
        self.state = .init(model: inputSource.model)
        super.init(state)
        input.subscribe(self, method: FilteredDuplicatesSource.update)
    }
    
    private func update() {
        if let previous = input.model.previous {
            if !isDuplicate(previous, input.model.current) {
                state.setModel(input.model.current)
            }
        } else {
            state.setModel(input.model.current)
        }
    }
}

public extension Source where Model: Equatable {
    func filteringDuplicates() -> Source<Model> {
        FilteredDuplicatesSource(inputSource: self, isDuplicate: { $0 == $1 } )
    }
}

public extension Source {
    func filteringDuplicates(using isDuplicate: @escaping (Model, Model) -> Bool) -> Source<Model> {
        FilteredDuplicatesSource(inputSource: self, isDuplicate: isDuplicate )
    }
}

//
//  FilteredSource.swift
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


/// A Source that filters upstream values using the provided closure.
final class FilteredSource<Model>: CustomSource {
    lazy var defaultModel: Model = {
        input.subscribe(self, method: FilteredSource.update, immediately: false)
        return input.model
    }()
    let input: Source<Model>
    let shouldInclude: (Model) -> Bool
    init(inputSource: Source<Model>, shouldInclude: @escaping (Model) -> Bool) {
        self.input = inputSource
        self.shouldInclude = shouldInclude
    }
    
    func update(value: Model) {
        if shouldInclude(value) {
            model = value
        }
    }
}

public extension Source {
    func filtering(using shouldInclude: @escaping (Model) -> Bool) -> Source<Model> {
        FilteredSource(inputSource: self, shouldInclude: shouldInclude).eraseToSource()
    }
}

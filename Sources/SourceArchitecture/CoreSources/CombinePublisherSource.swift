//
//  CombinePublisherSource.swift
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
import Combine


/// Provides a way to create a Source out of any Combine Publisher
final private class CombinePublisherSource<Input: Publisher>: SourceOf<Input.Output> {
    let initialModel: Model
    let input: Input
    var subscription: AnyCancellable?
    init(_ publisher: Input, initialModel: Model) {
        input = publisher
        self.initialModel = initialModel
        super.init()
        subscription = input.sink(receiveCompletion: { _ in } , receiveValue: { [weak self] in self?.model = $0 })
    }
}

public extension Publisher {
    func eraseToSource(initialValue: Output) -> Source<Output> {
        CombinePublisherSource(self, initialModel: initialValue).eraseToSource()
    }
}

private class PublishedWrapper<Value> {
    @Published var value: Value
    init(_ published: Published<Value>) {
        _value = published
    }
}

public extension Published {
    mutating func eraseToSource() -> Source<Value> {
        var published = PublishedWrapper(self)
        return CombinePublisherSource(self.projectedValue, initialModel: published.value).eraseToSource()
    }
}

public extension CurrentValueSubject {
    func eraseToSource() -> Source<Output> {
        CombinePublisherSource(self, initialModel: value).eraseToSource()
    }
}

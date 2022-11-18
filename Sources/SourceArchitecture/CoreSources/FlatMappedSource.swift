//
//  FlatMappedSource.swift
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


/// A Source that results from tranforming a value from another Source whenever that Source updates.  Different from a MappedSource because the transform method results not in a new value, but a new Source of a new value. For example, imagine wanting to transform a URL value into a new Source that fetches the URL. If you use a normal map, e.g. `urlSource.map { Fetchable<Value, Void>.fetching }` then the resulting Source<Fetchable<Value, Void>> would never update from .fetching to a new state. So you need to transform the urlSource's URL value not into a new _value_ but into a new Source of a Fetched value that will update from .fetching to .fetched or .error, etc.  That would be done by flatMapping, e.g. `urlSource.flatMap { ValueSource(url: $0) }` where ValueSource is a Source of a Fetchable value.
private final class FlatMappedSource<Input, Model>: SourceOf<Model> {

    @Source var input: Input
    @Threadsafe var mappedSource: Source<Model>?

    let transform: (Input) -> Source<Model>

    lazy var initialModel: Model =  {
        _input.subscribe(self, method: FlatMappedSource.updateSource, sendInitialModel: false)
        mappedSource = transform(input).subscribe(self, method: FlatMappedSource.updateModel, sendInitialModel: false)
        return mappedSource!.model
    }()

    init(input: Source<Input>, transform: @escaping (Input) -> Source<Model>) {
        _input = input
        self.transform = transform
    }
    
    func updateModel(value: Model) {
        model = value
    }
    
    func updateSource(input: Input) {
        mappedSource = transform(input).subscribe(self, method: FlatMappedSource.updateModel)
    }
}

public extension Source {
    /// Returns a Source which is regenerated every time this Source's model changes. For example, if you want to create a Source that fetches a URL every time a path string changes, you could use this method e.g. `pathSource.flatMap { path in FetchableDataSource(urlRequest: .init(URL(string: "https://somewhere.com/\($0)")!)) }`. This is different from a normal `map` function because it's not simply transforming one static value to another, but creating a new updating Source from a value everytime it changes
    func flatMap<T>(transform: @escaping (Model) -> Source<T>) -> Source<T> {
        FlatMappedSource(input: self, transform: transform).eraseToSource()
    }
}

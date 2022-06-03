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


/// A Source that results from tranforming a value from another Source whenever that Source updates.  Different from a MappedSource because the transform method results not in a new value, but a new Source of a new value. For example, imagine wanting to transform a URL value into a new Source that fetches the URL. If you use a normal map, e.g. `urlSource.map { Fetched<Value, Void>.fetching }` then the resulting Source<Fetched<Value, Void>> would never update from .fetching to a new state. So you need to transform the urlSource's URL value not into a new _value_ but into a new Source of a Fetched value that will update from .fetching to .fetched or .error, etc.  That would be done by flatMapping, e.g. `urlSource.flatMap { ValueSource(url: $0) }` where ValueSource is a Source of a Fetched value.
final class FlatMappedSource<Input, Model>: CustomSource {

    class Threadsafe: ThreadsafeProperties {
        var mappedSource: Source<Model>?
    }

    lazy var defaultModel: Model =  {
        input.subscribe(self, method: FlatMappedSource.updateSource, immediately: false)
        return transform(input.model).model
    }()
    let input: Source<Input>
    let transform: (Input) -> Source<Model>

    init(input: Source<Input>, transform: @escaping (Input) -> Source<Model>) {
        self.input = input
        self.transform = transform
        super.init()
    }
    
    func updateModel(value: Model) {
        model = value
    }
    
    func updateSource(input: Input) {
        threadsafe.mappedSource = transform(input)
        threadsafe.mappedSource?.subscribe(self, method: FlatMappedSource.updateModel)
    }
}

public extension Source {
    func flatMap<T>(transform: @escaping (Model) -> Source<T>) -> Source<T> {
        FlatMappedSource(input: self, transform: transform).eraseToSource()
    }
}

//
//  MappedSource.swift
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


private final class MappedSource<Model, NewModel>: SourceOf<NewModel> {

    @Source var input: Model

    let transform: (Model) -> NewModel

    lazy var initialModel = {
        _input.subscribe(self, method: MappedSource.update, sendInitialModel: false)
        return transform(input)
    }()

    init(_ input: Source<Model>, transform: @escaping (Model) -> NewModel) {
        _input = input
        self.transform = transform
    }

    func update(_ input: Model) {
        model = transform(input)
    }
}

public extension Source {
    /// Returns a new Source whose Model is the result of transforming the original Source's Model. Every time the original Source's model is updated, the new Source's model will also update.
    func map<NewModel>(_ transform: @escaping (Model) -> NewModel) -> Source<NewModel> {
        MappedSource(self, transform: transform).eraseToSource()
    }
}

//
//  MutableSource.swift
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


private final class _MutableSource<Model>: SourceOf<Mutable<Model>> {

    @Action(set) var setAction

    let initialValue: Model
    lazy var initialModel = Mutable(value: initialValue, set: setAction)

    public init(_ initialValue: Model) {
        self.initialValue = initialValue
    }

    private func set(_ value: Model) {
        model = .init(value: value, set: setAction)
    }
}

public final class MutableSource<Model>: ComposedSource<Mutable<Model>> {
    public init(_ initialValue: Model) {
        super.init{ _MutableSource(initialValue).eraseToSource() }
    }
}

public extension Source where Model: MutableRepresentable {
    func nonmutating() -> Source<Model.Value> {
        map { $0.asMutable().value }
    }
}

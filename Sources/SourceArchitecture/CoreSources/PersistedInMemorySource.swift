//
//  PersistedInMemorySource.swift
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


/// A Source that holds a value in memory and allows it to be written to, read from, and cleared
public final class PersistedInMemorySource<Value>: SourceOf<Persistable<Value>> {
    @ActionFromMethod(set) var setAction
    @ActionFromMethod(clear) var clearAction

    private let initialValue: Value?
    public lazy var initialModel: Persistable<Value> = initialValue.map { .found(.init(value: $0, isExpired: false, set: setAction, clear: clearAction)) } ?? .notFound(.init(set: setAction))

    public init(persistedValue: Value?) {
        self.initialValue = persistedValue
        super.init()
    }

    private func set(_ value: Value) {
        model = .found(.init(value: value, isExpired: false, set: setAction, clear: clearAction))
    }

    private func clear() {
        model = .notFound(.init(set: setAction))
    }
}

//
//  PrintUpdatesSource.swift
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


private final class PrintUpdateSource<Model>: SourceOf<Model> {

    @Source var input: Model

    let closure: (Model, Bool) -> String

    lazy var initialModel: Model = {
        print(closure(input, true))
        return input
    }()

    init(_ source: Source<Model>, closure: @escaping (Model, Bool) -> String) {
        _input = source
        self.closure = closure
        super.init()
        _input.subscribe(self, method: PrintUpdateSource.update, sendInitialModel: false)
    }

    func update(value: Model) {
        print(closure(value, false))
        model = value
    }
}

public extension Source {
    /// Returns the original Source but will print all changes to the model using a default message and formatting. In order to customize the printed description, pass in a `(Model) -> String` closure
    func _printingUpdates() -> Source<Model> {
        PrintUpdateSource(self, closure: { "Source Model of type \(Model.self) has \($1 ? "initial" : "updated") value: \($0)" }).eraseToSource()
    }

    /// Returns the original Source but will print all changes to the model using the provided closure to convert the Model value to a String description
    func _printingUpdates(_ closure: @escaping (Model) -> String) -> Source<Model> {
        PrintUpdateSource(self, closure: { model, _ in closure(model) } ).eraseToSource()
    }

    /// Returns the original Source but will print all changes to the model using the provided closure to convert the Model value to a String description. The closure accepts the Model value as the first parameter and a Bool value as the second parameter. The Bool value represents whether the Model instance being passed in is the initial value, or an updated / changed value.
    func _printingUpdates(_ closure: @escaping (Model, Bool) -> String) -> Source<Model> {
        PrintUpdateSource(self, closure: closure).eraseToSource()
    }
}

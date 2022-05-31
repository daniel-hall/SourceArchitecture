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


final class PrintUpdateSource<Model>: CustomSource {
    let input: Source<Model>
    let closure: (Model, Bool) -> String

    lazy var defaultModel: Model = {
        print(closure(input.model, true))
        return input.model
    }()

    init(_ source: Source<Model>, closure: @escaping (Model, Bool) -> String) {
        input = source
        self.closure = closure
        super.init()
        source.subscribe(self, method: PrintUpdateSource.update, shouldSendInitialValue: false)
    }

    func update(value: Model) {
        print(closure(value, false))
        model = value
    }
}

public extension Source {
    func printingUpdates(_ closure: @escaping (Model) -> String) -> Source<Model> {
        PrintUpdateSource(self, closure: { model, _ in closure(model) } ).eraseToSource()
    }

    func printingUpdates(_ closure: @escaping (Model, Bool) -> String) -> Source<Model> {
        PrintUpdateSource(self, closure: closure).eraseToSource()
    }

    func printingUpdates() -> Source<Model> {
        PrintUpdateSource(self, closure: { "Source Model of type \(Model.self) has \($1 ? "initial" : "updated") value: \($0)" }).eraseToSource()
    }
}

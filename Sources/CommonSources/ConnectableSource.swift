//
//  ConnectableSource.swift
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


final class ConnectableSource<Value>: Source<Connectable<Value>>, ActionSource {
    struct Actions: ActionMethods {
        fileprivate var connect = ActionMethod(ConnectableSource.connect)
        fileprivate var disconnect = ActionMethod(ConnectableSource.disconnect)
    }
    private struct MutableProperties {
        var source: Source<Value>?
    }
    private let sourceClosure: () -> Source<Value>
    private let state: MutableState<MutableProperties>
    
    init(_ sourceClosure: @escaping () -> Source<Value>) {
        self.sourceClosure = sourceClosure
        state = .init(mutableProperties: .init()) { state in
                .disconnected(.init(connect: state.connect))
        }
        super.init(state)
    }
    
    private func update() {
        guard let value = state.source?.model else { return }
        let model = Connectable<Value>.connected(.init(value: value, disconnect: state.disconnect))
        state.setModel(model)
    }
    
    private func disconnect() {
        state.source = nil
        let model = Connectable<Value>.disconnected(.init(connect: state.connect))
        state.setModel(model)
    }
    
    private func connect() {
        guard state.source == nil else {
            return
        }
        let newSource = self.sourceClosure()
        state.source = newSource
        newSource.subscribe(self, method: ConnectableSource.update)
    }
}

public func connectable<Value>(_ source: @escaping () -> Source<Value>) -> Source<Connectable<Value>> {
    ConnectableSource(source)
}

public func connectable<Value, Placeholder>(placeholder: Placeholder, _ source: @escaping () -> Source<Value>) -> Source<ConnectableWithPlaceholder<Value, Placeholder>> {
    ConnectableSource(source).addingPlaceholder(placeholder)
}

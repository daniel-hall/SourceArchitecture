//
//  ConnectableSource.swift
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


/// A type of Source which can create its contents when connected and clear them when disconnected. It is initialized with a closure that creates a Source. When the `connect` action is invoked, it will execute the closure to connect an input Source and forward its values. When `disconnect`is invoked, the input Source is set to nil, releasing the memory and stopping any behaviors
private final class _ConnectableSource<Value>: SourceOf<Connectable<Value>> {

    @Action(connect) var connectAction
    @Action(disconnect) var disconnectAction

    @Threadsafe var source: Source<Value>?

    lazy var initialModel: Connectable<Value> = .disconnected(.init(connect: connectAction))
    let sourceClosure: () -> Source<Value>

    init(_ sourceClosure: @escaping () -> Source<Value>) {
        self.sourceClosure = sourceClosure
    }

    func update(value: Value) {
        model = .connected(.init(value: value, disconnect: disconnectAction))
    }

    func disconnect() {
        source = nil
        model = .disconnected(.init(connect: connectAction))
    }

    func connect() {
        guard source == nil else {
            return
        }
        source = sourceClosure().subscribe(self, method: _ConnectableSource.update)
    }
}


/// Creates a Source of a `Connectable<Value>` from a closure that can create a `Source<Value>`. This allows any sort of initialization or other work managed by a Source to be deferred until `connect()` is called. It also allows the `Source<Value>` to be released when `disconnect()` is called. This frees up memory and processing until `connect()` is called again.  This type of behavior is very important in SwiftUI particularly for disconnecting Sources and freeing memory when List rows scroll off screen.
public final class ConnectableSource<Value>: ComposedSource<Connectable<Value>> {
    public init(_ sourceClosure: @escaping () -> Source<Value>) {
        super.init { _ConnectableSource(sourceClosure).eraseToSource() }
    }
}

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


public final class ConnectableSource<Value>: CustomSource {
    public class Actions: ActionMethods {
        fileprivate var connect = ActionMethod(ConnectableSource.connect)
        fileprivate var disconnect = ActionMethod(ConnectableSource.disconnect)
    }
    public class Threadsafe: ThreadsafeProperties {
        fileprivate var source: Source<Value>?
    }
    public lazy var defaultModel: Connectable<Value> = .disconnected(.init(connect: actions.connect))
    private let sourceClosure: () -> Source<Value>

    public init(_ sourceClosure: @escaping () -> Source<Value>) {
        self.sourceClosure = sourceClosure
        super.init()
    }

    private func update(value: Value) {
        model = .connected(.init(value: value, disconnect: actions.disconnect))
    }

    private func disconnect() {
        threadsafe.source = nil
        model = .disconnected(.init(connect: actions.connect))
    }

    private func connect() {
        guard threadsafe.source == nil else {
            return
        }
        threadsafe.source = sourceClosure()
        threadsafe.source?.subscribe(self, method: ConnectableSource.update)
    }
}

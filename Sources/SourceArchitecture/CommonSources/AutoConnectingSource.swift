//
//  AutoConnectingSource.swift
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


internal final class AutoConnectingSource<Model>: CustomSource {
    private let connectable: Source<Connectable<Model>>
    lazy var defaultModel: Model = {
        connectable.model.connect()
        connectable.subscribe(self, method: AutoConnectingSource.update, shouldSendInitialValue: false)
        return connectable.model.connected!.value
    }()
    init(_ connectable: Source<Connectable<Model>>) {
        self.connectable = connectable
    }

    func update(_ value: Connectable<Model>) {
        value.connected.map { model = $0.value }
    }
}

public extension Source where Model: ConnectableRepresentable  {
    func autoConnecting() -> Source<Model.Value> {
        AutoConnectingSource(map { $0.asConnectable() }).eraseToSource()
    }
}

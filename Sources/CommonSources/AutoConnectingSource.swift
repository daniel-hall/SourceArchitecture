//
//  AutoConnectingSource.swift
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


final class AutoConnectingSource<Model>: Source<Model> {
    let state: State
    let connectableSource: Source<Connectable<Model>>
    init(_ source: Source<Connectable<Model>>) {
        connectableSource = source
        var subscribe: (() -> Void)?
        state = .init { _ in
            try? source.model.connect()
            subscribe?()
            return source.model.connected!.value
        }
        super.init(state)
        subscribe = { [weak self] in
            guard let self = self else { return }
            source.subscribe(self, method: AutoConnectingSource.update)
        }
    }

    private func update() {
        guard let value = connectableSource.model.connected?.value else { return }
        state.setModel(value)
    }
}

public func deferred<T>(_ source: @escaping () -> Source<T>) -> Source<T> {
    AutoConnectingSource(connectable(source))
}

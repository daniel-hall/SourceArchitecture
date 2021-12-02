//
//  OnConnectSource.swift
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


/// A Source that applies a provided transformation to a connectable Source at the time that Source is connected. Example, a Source<Fetchable<Model>> has extension methods like .retrying() and .refreshing(every:). However, a Source<Connectable<Fetchable<Model>>> doesn't have methods like that and operations like retrying and refreshing don't even make sense for a disconnected Source.  Therefore, OnConnectSource allows us to provide a transformation of the signature `(Source<Fetchable<Model>>) -> Source<Fetchable<Model>>` that will run only when the Source<Connectable<Fetchable<Model>>> is connected. E.g. Source<Connectable<Fetchable<Model>>>.onConnect { $0.refreshing(every: 10) }
final class OnConnectSource<Model>: Source<Connectable<Model>> {
    private struct MutableProperties {
        var connectedSource: Source<Model>?
        var mutableSource: MutableValueSource<Model>?
    }
    private let modification: (Source<Model>) -> Source<Model>
    private let inputSource: Source<Connectable<Model>>
    private let state: MutableState<MutableProperties>
    
    init(_ source: Source<Connectable<Model>>, modification: @escaping(Source<Model>) -> Source<Model>) {
        self.modification = modification
        self.inputSource = source
        state = .init(mutableProperties: .init(), model: source.model)
        super.init(state)
        source.subscribe(self, method: OnConnectSource.update)
    }
    
    private func publish() {
        guard let model = state.connectedSource?.model, let connected = inputSource.model.connected else { return }
        state.setModel(Connectable.connected(.init(value: model, disconnect: connected.disconnect)))
    }
    
    private func update() {
        let model = inputSource.model
        switch model {
        case .disconnected:
            state.connectedSource = nil
            state.mutableSource = nil
            state.setModel(model)
        case .connected(let connected):
            if let mutableSource = state.mutableSource {
                mutableSource.setValue(connected.value)
            } else {
                let mutableSource = MutableValueSource(value: connected.value)
                let connectedSource = self.modification(mutableSource)
                state.mutableSource = mutableSource
                state.connectedSource = connectedSource
                connectedSource.subscribe(self, method: OnConnectSource.publish)
            }
        }
    }
}

public extension Source where Model: ConnectableWithPlaceholderRepresentable & ConnectableRepresentable {
    func onConnect(_ modify: @escaping (Source<Model.Value>) -> Source<Model.Value>) -> Source<ConnectableWithPlaceholder<Model.Value, Model.Placeholder>> {
        return OnConnectSource(self.map { $0.asConnectable() }, modification: modify).addingPlaceholder(model.asConnectableWithPlaceholder().placeholder)
    }
}

public extension Source where Model: ConnectableRepresentable {
    @_disfavoredOverload func onConnect(_ modify: @escaping (Source<Model.Value>) -> Source<Model.Value>) -> Source<Connectable<Model.Value>> {
        OnConnectSource(self.map { $0.asConnectable() }, modification: modify)
    }
}

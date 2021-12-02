//
//  RefreshingSource.swift
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


/// A Source that will automatically refresh its Fetched value using a specified interval.
final class RefreshingSource<Value>: Source<Fetchable<Value>> {
    private struct MutableProperties {
        fileprivate var refreshWorkItem: DispatchWorkItem?
    }
    private let state: MutableState<MutableProperties>
    private let source: Source<Fetchable<Value>>
    private let refreshInterval: TimeInterval
    
    public init(source: Source<Fetchable<Value>>, interval: TimeInterval) {
        refreshInterval = interval
        self.source = source
        state = .init(mutableProperties: .init(), model: source.model)
        super.init(state)
        let workItem = DispatchWorkItem { [weak self] in self?.update() }
        state.refreshWorkItem = workItem
        source.subscribe(self, method: RefreshingSource.sourceUpdate)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval, execute: workItem)
    }
    
    private func sourceUpdate() {
        state.setModel(source.model)
    }
    
    private func update() {
        try? source.model.fetched?.refresh()
        state.refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.update() }
        state.refreshWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + refreshInterval, execute: workItem)
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable & FetchableRepresentable {
    func refreshing(every interval: TimeInterval) -> Source<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        RefreshingSource(source: map { $0.asFetchable() }, interval: interval).addingPlaceholder().mapFetchablePlaceholder { self.model.asFetchableWithPlaceholder().placeholder }
    }
}

public extension Source where Model: FetchableRepresentable {
    @_disfavoredOverload func refreshing(every interval: TimeInterval) -> Source<Fetchable<Model.Value>> {
        RefreshingSource(source: map { $0.asFetchable() }, interval: interval)
    }
}

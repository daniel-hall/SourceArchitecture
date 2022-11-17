//
//  RefreshingSource.swift
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


/// A Source that will automatically refresh its Fetched value using a specified interval.
private final class RefreshingSource<Value>: SourceOf<Fetchable<Value>> {

    @Threadsafe var refreshWorkItem: DispatchWorkItem?
    @Source var fetchableValue: Fetchable<Value>

    let refreshInterval: TimeInterval

    lazy var initialModel = {
        _fetchableValue.subscribe(self, method: RefreshingSource.sourceUpdate)
        return model
    }()
    
    init(source: Source<Fetchable<Value>>, interval: TimeInterval) {
        refreshInterval = interval
        _fetchableValue = source
        super.init()
        let workItem = DispatchWorkItem { [weak self] in self?.update() }
        refreshWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + interval, execute: workItem)
    }
    
    func sourceUpdate(value: Fetchable<Value>) {
        self.model = value
    }
    
    func update() {
        fetchableValue.fetched?.refresh?()
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.update() }
        refreshWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + refreshInterval, execute: workItem)
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable {
    /// Automatically refreshes / polls the Fetchable value at the specified interval
    func refreshing(every interval: TimeInterval) -> Source<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        RefreshingSource(source: map { $0.asFetchableWithPlaceholder().asFetchable() }, interval: interval).eraseToSource().addingPlaceholder().mapFetchablePlaceholder { self.model.asFetchableWithPlaceholder().placeholder }
    }
}

public extension Source where Model: FetchableRepresentable {
    /// Automatically refreshes / polls the Fetchable value at the specified interval
    @_disfavoredOverload func refreshing(every interval: TimeInterval) -> Source<Fetchable<Model.Value>> {
        RefreshingSource(source: map { $0.asFetchable() }, interval: interval).eraseToSource()
    }
}

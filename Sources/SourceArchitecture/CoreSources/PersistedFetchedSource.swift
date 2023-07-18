//
//  SourceArchitecture
//
//  Copyright (c) 2023 Daniel Hall
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


/// A Source that automatically reads and writes a Fetchable value from and to persistence, or from the Network (or other channel for fetching) as needed. Defaults to using the persisted value when it exists and in such a case will never make a network request. Will make a network request if the persisted value is not found or is expired. Will make a network request if refresh() is explicitly called on the model.
private final class PersistedFetchedSource<Value>: Source<Fetchable<Value>> {

    @ActionFromMethod(refresh) var refreshAction
    @Sourced(updating: updateFetched) var fetchableSource: Fetchable<Value>?
    @Sourced var persisted: Persistable<Value>

    let fetchClosure: () -> AnySource<Fetchable<Value>>

    fileprivate let initialState: Fetchable<Value> = .fetching(.init(progress: nil))

    func onStart() {
        updatePersisted(persisted)
    }

    fileprivate init(fetched: @escaping @autoclosure () -> AnySource<Fetchable<Value>>, persisted: AnySource<Persistable<Value>>) {
        _persisted = .init(from: persisted, updating: PersistedFetchedSource.updatePersisted)
        fetchClosure = fetched
    }
    
    private func subscribeFetched() {
        _fetchableSource.setSource(fetchClosure())
        fetchableSource?.fetched?.refresh?()
    }
    
    private func updatePersisted(_ value: Persistable<Value>) {
        switch value {
        case .notFound:
            subscribeFetched()
        case .found(let found):
            state = .fetched(.init(value: found.value, refresh: refreshAction))
            if found.isExpired {
                refresh()
            }
        }
    }
    
    private func updateFetched(value: Fetchable<Value>) {
        switch value {
        case .failure(let failure): state = .failure(failure)
        case .fetching(let fetching):
            if case .notFound = persisted {
                state = .fetching(fetching)
            }
        case .fetched(let fetched):
            _fetchableSource.clearSource()
            persisted.set(fetched.value)
        }
    }
    
    private func refresh() {
        subscribeFetched()
    }
}

public extension AnySource where Model: FetchableRepresentable {
    /// Returns a Source that reads and writes this Source's value to the provided persistence. If a non-expired value already exists in the persistence, then the fetch will never be executed. If a persisted value doesn't exist or `refresh()` is called on the model, the the fetched value will be written to persistence after it is retrieved.
    @_disfavoredOverload
    func persisted(using persistableSource: AnySource<Persistable<Model.Value>>) -> AnySource<Fetchable<Model.Value>> {
        PersistedFetchedSource(fetched: self.map { $0.asFetchable() }, persisted: persistableSource).eraseToAnySource()
    }
}

public extension AnySource where Model: FetchableWithPlaceholderRepresentable {
    /// Returns a Source that reads and writes this Source's value to the provided persistence. If a non-expired value already exists in the persistence, then the fetch will never be executed. If a persisted value doesn't exist or `refresh()` is called on the model, the the fetched value will be written to persistence after it is retrieved.
    func persisted(using persistableSource: AnySource<Persistable<Model.Value>>) -> AnySource<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        PersistedFetchedSource(fetched: self.map { $0.asFetchableWithPlaceholder().asFetchable() }, persisted: persistableSource).eraseToAnySource().addingPlaceholder(state.asFetchableWithPlaceholder().placeholder)
    }
}

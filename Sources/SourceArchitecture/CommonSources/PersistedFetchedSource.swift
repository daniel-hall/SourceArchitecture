//
//  PersistedFetchedSource.swift
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


/// A Source that automatically reads and writes a Fetchable value from and to persistence, or from the Network (or other channel for fetching) as needed. Defaults to using the persisted value when it exists and in such a case will never make a network request. Will make a network request if the persisted value is not found or is expired. Will make a network request if refresh() is explicitly called on the model.
internal final class PersistedFetchedSource<Value>: CustomSource {
    
    internal class Actions: ActionMethods {
        fileprivate var refresh = ActionMethod(PersistedFetchedSource.refresh)
    }
    
    internal class Threadsafe: ThreadsafeProperties {
        fileprivate var fetchableSource: Source<Fetchable<Value>>?
    }

    lazy var defaultModel: Fetchable<Value> = {
        persisted.subscribe(self, method: PersistedFetchedSource.updatePersisted)
        return model
    }()

    private let persisted: Source<Persistable<Value>>
    private let fetchClosure: () -> Source<Fetchable<Value>>

    internal init(fetched: @escaping @autoclosure () -> Source<Fetchable<Value>>, persisted: Source<Persistable<Value>>) {
        self.persisted = persisted
        fetchClosure = fetched
    }
    
    private func subscribeFetched() {
        if threadsafe.fetchableSource == nil {
            threadsafe.fetchableSource = fetchClosure()
        }
        threadsafe.fetchableSource?.model.fetched?.refresh()
        threadsafe.fetchableSource?.subscribe(self, method: PersistedFetchedSource.updateFetched)
    }
    
    private func updatePersisted(_ value: Persistable<Value>) {
        switch value {
        case .notFound:
            subscribeFetched()
        case .found(let found):
            model = .fetched(.init(value: found.value, refresh: actions.refresh))
            if found.isExpired {
                refresh()
            }
        }
    }
    
    private func updateFetched(value: Fetchable<Value>) {
        switch value {
        case .failure(let failure): model = .failure(failure)
        case .fetching(let fetching):
            if case .notFound = persisted.model {
                model = .fetching(fetching)
            }
        case .fetched(let fetched): persisted.model.set(fetched.value)
        }
    }
    
    private func refresh() {
        subscribeFetched()
    }
}

public extension Source where Model: FetchableRepresentable {
    @_disfavoredOverload
    func persisted(using persistableSource: Source<Persistable<Model.Value>>) -> Source<Fetchable<Model.Value>> {
        PersistedFetchedSource(fetched: self.map { $0.asFetchable() }, persisted: persistableSource).eraseToSource()
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable {
    func persisted(using persistableSource: Source<Persistable<Model.Value>>) -> Source<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        PersistedFetchedSource(fetched: self.map { $0.asFetchableWithPlaceholder().asFetchable() }, persisted: persistableSource).eraseToSource().addingPlaceholder(model.asFetchableWithPlaceholder().placeholder)
    }
}

//
//  PersistedFetchedSource.swift
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


/// A Source that automatically reads and writes a Fetchable value from and to persistence, or from the Network (or other channel for fetching) as needed. Defaults to using the persisted value when it exists and in such a case will never make a network request. Will make a network request if the persisted value is not found or is expired. Will make a network request if refresh() is explicitly called on the model.
final class PersistedFetchedSource<Value>: Source<Fetchable<Value>>, ActionSource {
    
    struct Actions: ActionMethods {
        var refresh = ActionMethod(PersistedFetchedSource.refresh)
    }
    
    private struct MutableProperties {
        var fetched: Source<Fetchable<Value>>?
    }
    
    private let state: MutableState<MutableProperties>
    private let persisted: Source<Persistable<Value>>
    private let fetched: () -> Source<Fetchable<Value>>
    
    init(fetchedSource: @escaping @autoclosure () -> Source<Fetchable<Value>>, persistedSource: Source<Persistable<Value>>) {
        persisted = persistedSource
        fetched = fetchedSource
        state = .init(mutableProperties: .init(), model: .fetching(.init(progress: nil)))
        super.init(state)
        persisted.subscribe(self, method: PersistedFetchedSource.updatePersisted)
    }
    
    private func subscribeFetched() {
        if state.fetched == nil {
            state.fetched = fetched()
        }
        try? state.fetched?.model.fetched?.refresh()
        state.fetched?.subscribe(self, method: PersistedFetchedSource.updateFetched)
    }
    
    private func updatePersisted() {
        switch persisted.model {
        case .notFound:
            subscribeFetched()
        case .found(let found):
            state.setModel(.fetched(.init(value: found.value, refresh: state.refresh)))
            if found.isExpired {
                refresh()
            }
        }
    }
    
    private func updateFetched() {
        switch state.fetched?.model {
        case .failure(let failure): state.setModel(.failure(failure))
        case .fetching(let fetching):
            if case .notFound = persisted.model {
                state.setModel(.fetching(fetching))
            }
        case .fetched(let fetched): try? persisted.model.set(fetched.value)
        case .none: break
        }
    }
    
    private func refresh() {
        subscribeFetched()
    }
}

//
//  NetworkSyncedPersistedSource.swift
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
#if canImport(UIKit)
import UIKit
#endif


public protocol Versioned {
    associatedtype Version: Comparable
    var version: Version { get }
}

private final class _NetworkSyncedPersistableSource<Value: Versioned>: SourceOf<Persistable<Value>> {

    @ActionFromMethod(set) var setAction
    @ActionFromMethod(clear) var clearAction

    @Threadsafe var currentFetchableValue: Source<Fetchable<Value>>?
    @Threadsafe var currentFetchableOptionalValue: Source<Fetchable<Value?>>?

    @Source var persisted: CurrentAndPrevious<Persistable<Value>>
    
    let get: () -> Source<Fetchable<Value?>>
    let create: (Value) -> Source<Fetchable<Value>>
    let update: (Value) -> Source<Fetchable<Value>>
    let delete: (Value) -> Source<Fetchable<Value>>

    lazy var initialModel = {
        _persisted.subscribe(self, method: _NetworkSyncedPersistableSource.handlePersistenceUpdate)
        currentFetchableOptionalValue = get()
        currentFetchableOptionalValue?.subscribe(self, method: _NetworkSyncedPersistableSource.handleFetchableOptionalValue)
        return model
    }()

    init(persisted: Source<Persistable<Value>>, get: @escaping () -> Source<Fetchable<Value?>>, create: @escaping (Value) -> Source<Fetchable<Value>>, update: @escaping (Value) -> Source<Fetchable<Value>>, delete: @escaping (Value) -> Source<Fetchable<Value>>) {
        _persisted = persisted.currentAndPrevious()
        self.get = get
        self.create = create
        self.update = update
        self.delete = delete
        super.init()
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
    }

    @objc func didBecomeActive() {
        currentFetchableOptionalValue = get()
        currentFetchableOptionalValue?.subscribe(self, method: _NetworkSyncedPersistableSource.handleFetchableOptionalValue)
    }

    func handleFetchableOptionalValue(value: Fetchable<Value?>) {
        switch value {
        case .fetched(let fetched):
            if let value = fetched.value {
                guard let found = persisted.current.found else {
                    // If we just deleted, don't save the value that was returned
                    if persisted.current.notFound != nil, persisted.previous?.found != nil {
                        return
                    }
                    persisted.set(value)
                    return
                }
                if value.version > found.version {
                    found.set(value)
                } else if value.version < found.version {
                    currentFetchableValue = self.update(value)
                    currentFetchableValue?.subscribe(self, method: _NetworkSyncedPersistableSource.handleFetchableValue)
                }
                return
            }
            // If there is a nil response from the GET, then CREATE a synced record
            if let found = persisted.current.found {
                currentFetchableValue = create(found.value)
                currentFetchableValue?.subscribe(self, method: _NetworkSyncedPersistableSource.handleFetchableValue)
            }
        case .failure(let failure):
            if let notFound = persisted.current.notFound, notFound.error?.localizedDescription != failure.error.localizedDescription {
                self.model = .notFound(.init(error: failure.error, set: setAction))
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                    failure.retry?()
                }
            }
        case .fetching: return
        }
    }

    func handleFetchableValue(value: Fetchable<Value>) {
        switch value {
        case .fetching: return
        case .failure: return
        case .fetched(let fetched):
            // If we just deleted, don't update with the value that was returned
            if persisted.current.notFound != nil, persisted.previous?.found != nil {
                return
            }
            guard let found = persisted.current.found else {
                persisted.set(fetched.value)
                return
            }
            if fetched.value.version >= found.version {
                persisted.set(fetched.value)
            } else {
                currentFetchableValue = update(found.value)
                currentFetchableValue?.subscribe(self, method: _NetworkSyncedPersistableSource.handleFetchableValue)
            }
        }
    }

    func handlePersistenceUpdate(update: CurrentAndPrevious<Persistable<Value>>) {
        switch update.current {
        case .found(let found): model = .found(.init(value: found.value, isExpired:  found.isExpired, set: setAction, clear: clearAction))
        case .notFound(let notFound):
            model = .notFound(.init(error: notFound.error, set: setAction))
            if let previous = update.previous?.found?.value {
                currentFetchableValue = delete(previous)
            }
        }
    }

    func set(value: Value) {
        switch persisted.current {
        case .notFound:
            persisted.current.set(value)
        case .found(let found):
            if value.version > found.value.version {
                persisted.current.set(value)
                currentFetchableValue = self.update(value)
                currentFetchableValue?.subscribe(self, method: _NetworkSyncedPersistableSource.handleFetchableValue)
            }
        }
    }

    func clear() {
        guard case .found(let found) = model else { return }
        persisted.current.clear?()
        currentFetchableValue = delete(found.value)
    }
}

public final class NetworkSyncedPersistableSource<Value: Versioned>: ComposedSource<Persistable<Value>> {
    public init (
        persisted: Source<Persistable<Value>>,
        get: @escaping () -> Source<Fetchable<Value?>>,
        create: @escaping (Value) -> Source<Fetchable<Value>>,
        update: @escaping (Value) -> Source<Fetchable<Value>>,
        delete: @escaping (Value) -> Source<Fetchable<Value>>
    ) {
        super.init { _NetworkSyncedPersistableSource(persisted: persisted, get: get, create: create, update: update, delete: delete).eraseToSource() }
    }
}

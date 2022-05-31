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

public final class NetworkSyncedPersistableSource<Value: Versioned>: CustomSource {

    public class Threadsafe: ThreadsafeProperties {
        fileprivate var currentFetchableValue: Source<Fetchable<Value>>?
        fileprivate var currentFetchableOptionalValue: Source<Fetchable<Value?>>?
    }

    public class Actions: ActionMethods {
        fileprivate var set = ActionMethod(NetworkSyncedPersistableSource.set)
        fileprivate var clear = ActionMethod(NetworkSyncedPersistableSource.clear)
    }

    public lazy var defaultModel: Persistable<Value> = {
        persisted.subscribe(self, method: NetworkSyncedPersistableSource.handlePersistenceUpdate)
        threadsafe.currentFetchableOptionalValue = get()
        threadsafe.currentFetchableOptionalValue?.subscribe(self, method: NetworkSyncedPersistableSource.handleFetchableOptionalValue)
        return model
    }()
    private let persisted: Source<CurrentAndPrevious<Persistable<Value>>>
    private let get: () -> Source<Fetchable<Value?>>
    private let create: (Value) -> Source<Fetchable<Value>>
    private let update: (Value) -> Source<Fetchable<Value>>
    private let delete: (Value) -> Source<Fetchable<Value>>


    public init(persisted: Source<Persistable<Value>>, get: @escaping () -> Source<Fetchable<Value?>>, create: @escaping (Value) -> Source<Fetchable<Value>>, update: @escaping (Value) -> Source<Fetchable<Value>>, delete: @escaping (Value) -> Source<Fetchable<Value>>) {
        self.persisted = persisted.currentAndPrevious()
        self.get = get
        self.create = create
        self.update = update
        self.delete = delete
        super.init()
        #if canImport(UIKit)
            NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
    }

    @objc private func didBecomeActive() {
        threadsafe.currentFetchableOptionalValue = get()
        threadsafe.currentFetchableOptionalValue?.subscribe(self, method: NetworkSyncedPersistableSource.handleFetchableOptionalValue)
    }

    private func handleFetchableOptionalValue(value: Fetchable<Value?>) {
        switch value {
        case .fetched(let fetched):
            if let value = fetched.value {
                guard let found = persisted.model.current.found else {
                    // If we just deleted, don't save the value that was returned
                    if persisted.model.current.notFound != nil, persisted.model.previous?.found != nil {
                        return
                    }
                    persisted.model.set(value)
                    return
                }
                if value.version > found.version {
                    found.set(value)
                } else if value.version < found.version {
                    threadsafe.currentFetchableValue = self.update(value)
                    threadsafe.currentFetchableValue?.subscribe(self, method: NetworkSyncedPersistableSource.handleFetchableValue)
                }
                return
            }
            // If there is a nil response from the GET, then CREATE a synced record
            if let found = persisted.model.current.found {
                threadsafe.currentFetchableValue = create(found.value)
                threadsafe.currentFetchableValue?.subscribe(self, method: NetworkSyncedPersistableSource.handleFetchableValue)
            }
        case .failure(let failure):
            if let notFound = persisted.model.current.notFound, notFound.error?.localizedDescription != failure.error.localizedDescription {
                self.model = .notFound(.init(error: failure.error, set: actions.set))
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
                    failure.retry?()
                }
            }
        case .fetching: return
        }
    }

    private func handleFetchableValue(value: Fetchable<Value>) {
        switch value {
        case .fetching: return
        case .failure: return
        case .fetched(let fetched):
            // If we just deleted, don't update with the value that was returned
            if persisted.model.current.notFound != nil, persisted.model.previous?.found != nil {
                return
            }
            guard let found = persisted.model.current.found else {
                persisted.model.set(fetched.value)
                return
            }
            if fetched.value.version >= found.version {
                persisted.model.set(fetched.value)
            } else {
                threadsafe.currentFetchableValue = update(found.value)
                threadsafe.currentFetchableValue?.subscribe(self, method: NetworkSyncedPersistableSource.handleFetchableValue)
            }
        }
    }

    private func handlePersistenceUpdate(update: CurrentAndPrevious<Persistable<Value>>) {
        switch update.current {
        case .found(let found): model = .found(.init(value: found.value, isExpired: { found.isExpired }, set: actions.set, clear: actions.clear))
        case .notFound(let notFound):
            model = .notFound(.init(error: notFound.error, set: actions.set))
            if let previous = update.previous?.found?.value {
                threadsafe.currentFetchableValue = delete(previous)
            }
        }
    }

    private func set(value: Value) {
        switch persisted.model.current {
        case .notFound:
            persisted.model.current.set(value)
        case .found(let found):
            if value.version > found.value.version {
                persisted.model.current.set(value)
                threadsafe.currentFetchableValue = self.update(value)
                threadsafe.currentFetchableValue?.subscribe(self, method: NetworkSyncedPersistableSource.handleFetchableValue)
            }
        }
    }

    private func clear() {
        guard case .found(let found) = model else { return }
        persisted.model.current.clear?()
        threadsafe.currentFetchableValue = delete(found.value)
    }
}

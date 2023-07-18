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
#if canImport(UIKit)
import UIKit
#endif


public protocol Versioned {
    associatedtype Version: Comparable
    var version: Version { get }
}

private final class _NetworkSyncedPersistableSource<Value: Versioned>: Source<Persistable<Value>>, @unchecked Sendable {

    @ActionFromMethod(set) var setAction
    @ActionFromMethod(clear) var clearAction

    @Sourced(updating: handleFetchableValue) var currentFetchableValue: Fetchable<Value>?
    @Sourced(updating: handleFetchableOptionalValue) var currentFetchableOptionalValue: Fetchable<Value?>?

    @Sourced var persisted: CurrentAndPrevious<Persistable<Value>>
    
    let get: () -> AnySource<Fetchable<Value?>>
    let create: (Value) -> AnySource<Fetchable<Value>>
    let update: (Value) -> AnySource<Fetchable<Value>>
    let delete: (Value) -> AnySource<Fetchable<Value>>

    lazy var initialState = {
        _currentFetchableOptionalValue.setSource(get())
        return state
    }()

    init(persisted: AnySource<Persistable<Value>>, get: @escaping () -> AnySource<Fetchable<Value?>>, create: @escaping (Value) -> AnySource<Fetchable<Value>>, update: @escaping (Value) -> AnySource<Fetchable<Value>>, delete: @escaping (Value) -> AnySource<Fetchable<Value>>) {
        _persisted = .init(from: persisted.currentAndPrevious(), updating: _NetworkSyncedPersistableSource.handlePersistenceUpdate)
        self.get = get
        self.create = create
        self.update = update
        self.delete = delete
        super.init()
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
        handlePersistenceUpdate(update: self.persisted)
    }

    @objc func didBecomeActive() {
        _currentFetchableOptionalValue.setSource(get())
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
                    persisted.current.set(value)
                    return
                }
                if value.version > found.value.version {
                    found.set(value)
                } else if value.version < found.value.version {
                    _currentFetchableValue.setSource(self.update(value))
                }
                return
            }
            // If there is a nil response from the GET, then CREATE a synced record
            if let found = persisted.current.found {
                _currentFetchableValue.setSource(create(found.value))
            }
        case .failure(let failure):
            if let notFound = persisted.current.notFound, notFound.error?.localizedDescription != failure.error.localizedDescription {
                self.state = .notFound(.init(error: failure.error, set: setAction))
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
                persisted.current.set(fetched.value)
                return
            }
            if fetched.value.version >= found.value.version {
                persisted.current.set(fetched.value)
            } else {
                _currentFetchableValue.setSource(update(found.value))
            }
        }
    }

    func handlePersistenceUpdate(update: CurrentAndPrevious<Persistable<Value>>) {
        switch update.current {
        case .found(let found): state = .found(.init(value: found.value, isExpired:  found.isExpired, set: setAction, clear: clearAction))
        case .notFound(let notFound):
            state = .notFound(.init(error: notFound.error, set: setAction))
            if let previous = update.previous?.found?.value {
                _ = delete(previous).state
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
                _currentFetchableValue.setSource(self.update(value))
            }
        }
    }

    func clear() {
        guard case .found(let found) = state else { return }
        persisted.current.clear?()
        _ = delete(found.value).state
    }
}

public final class NetworkSyncedPersistableSource<Value: Versioned>: ComposedSource<Persistable<Value>> {
    public init (
        persisted: AnySource<Persistable<Value>>,
        get: @escaping () -> AnySource<Fetchable<Value?>>,
        create: @escaping (Value) -> AnySource<Fetchable<Value>>,
        update: @escaping (Value) -> AnySource<Fetchable<Value>>,
        delete: @escaping (Value) -> AnySource<Fetchable<Value>>
    ) {
        super.init { _NetworkSyncedPersistableSource(persisted: persisted, get: get, create: create, update: update, delete: delete).eraseToAnySource() }
    }
}

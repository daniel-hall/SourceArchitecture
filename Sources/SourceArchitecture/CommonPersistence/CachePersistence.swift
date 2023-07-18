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
import Combine
#if canImport(UIKit)
import UIKit
#endif


// A type to describe how an item should be cached (expiration time, retention policy, etc.)
public struct CacheDescriptor {

    public enum CacheRetentionPolicy: Comparable {
        case discardFirst
        case discardUnderMemoryPressure
        case discardLast
        case discardNever
    }

    let key: String
    let retentionPolicy: CacheRetentionPolicy
    let expireAfter: TimeInterval?
    
    public init(key: String, expireAfter: TimeInterval? = nil, retentionPolicy: CacheRetentionPolicy = .discardUnderMemoryPressure) {
        self.key = key
        self.expireAfter = expireAfter
        self.retentionPolicy = retentionPolicy
    }
}

/// A protocol that includes possible generic options for configuring CachePersistence
public protocol CachePersistenceOptions { }

/// An option that allows the CachePersistence to be configured with a maximum size
public struct WithMaxSize: CachePersistenceOptions {
    fileprivate let maxSize: Int
}

/// A protocol that must be adopted by any values that will be stored in a CachePersistence configured with a maximum size. The protocol reports the size (in bytes) of the value
public protocol CacheSizeRepresentable {
    var cacheSize: Int { get }
}

/// An option that allows the CachePersistence to be configured with a maximum number of cached items
public struct WithMaxCount: CachePersistenceOptions {
    fileprivate let maxCount: Int
}

/// An option that allows the CachePersistence to be configured with a maximum size and a maximum number of cached items
public struct WithMaxSizeAndMaxCount: CachePersistenceOptions {
    fileprivate let maxSize: Int
    fileprivate let maxCount: Int
}

/// An option that specifies that a CachePersistence should have no limits to the size it occupies or number of items. It will still respond to low memory notifications however.
public struct WithUnlimitedSizeAndCount: CachePersistenceOptions { }


/// A Source-based implementation of caching that can optionally flush items to keep within a count or size limit
public class CachePersistence<Options: CachePersistenceOptions> {
    private let lock = NSRecursiveLock()
    private var dictionary = [String: WeakCacheSource]()
    private var _maxCount: Int?
    private var _maxSize: Int?
    private var _currentSize: Int {
        lock.lock()
        defer { lock.unlock() }
        return dictionary.reduce(0) { $0 + ($1.value.source?.state.size ?? 0) }
    }

    private var _currentCount: Int {
        dictionary.count
    }

    // Sort in order of which items should be flushed first (empty, expired, lower priority, older)
    private var sortedItems: [(key: String, value: WeakCacheSource)] {
        dictionary = dictionary.filter { !$0.value.isReleased }
        return dictionary.sorted {
            guard let first = $0.1.source?.state, let second = $1.1.source?.state else { return true }
            return (first.isExpired && !second.isExpired )
            || (first.isExpired && second.isExpired )
            || (first.retentionPolicy < second.retentionPolicy && !second.isExpired)
            || (first.retentionPolicy == second.retentionPolicy && !second.isExpired && first.dateLastSet < second.dateLastSet )
        }
    }

    private var adjustmentWorkItem: DispatchWorkItem?

    public init(_ options: Options) {
        switch options {
        case let options as WithMaxSize:
            _maxSize = options.maxSize
        case let options as WithMaxSizeAndMaxCount:
            _maxSize = options.maxSize
            _maxCount = options.maxCount
        case let options as WithMaxCount:
            _maxCount = options.maxCount
        default: break
        }
#if canImport(UIKit)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
#endif
    }

    private func adjustCount() {
        lock.lock()
        defer { lock.unlock() }
        var currentCount = _currentCount
        guard let maxCount = _maxCount, currentCount > maxCount else { return }
        var sorted = sortedItems
        while currentCount > maxCount, sorted.count > 0 {
            let next = sorted.removeFirst()
            dictionary[next.key]?.source?.state.clear()
            dictionary[next.key] = nil
            currentCount -= 1
        }
    }

    private func adjustSize() {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .memory
        var currentSize = _currentSize
        guard let maxSize = _maxSize, currentSize > maxSize else {
            return
        }
        var sorted = sortedItems
        while currentSize > maxSize, sorted.count > 0 {
            let next = sorted.removeFirst()
            defer {
                dictionary[next.key]?.source?.state.clear()
                dictionary[next.key] = nil
            }
            if let size = next.value.source?.state.size {
                currentSize -= size
            }
        }
    }

    // If low memory, discard all items of lower priority
    @objc private func handleLowMemory() {
        lock.lock()
        sortedItems.prefix { ($0.value.source?.state.retentionPolicy ?? .discardFirst) <= .discardUnderMemoryPressure
        }.forEach {
            dictionary[$0.key]?.source?.state.clear()
            dictionary[$0.key] = nil
        }
        lock.unlock()
    }

    private func retrieve(_ descriptor: CacheDescriptor) -> AnySource<CachedItem> {
        lock.lock()
        let updateClosure: () -> Void = { [weak self] in
            self?.lock.lock()
            self?.adjustmentWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                self?.adjustCount()
                self?.adjustSize()
            }
            self?.adjustmentWorkItem = workItem
            self?.lock.unlock()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: workItem)
        }
        defer {
            lock.unlock()
            updateClosure()
        }
        guard let source = dictionary[descriptor.key]?.source else {
            let newItem = WeakCacheSource(updateClosure: updateClosure)
            let source = newItem.source!
            newItem.release()
            dictionary[descriptor.key] = newItem
            return source
        }
        return source
    }
}

// MARK: — WeakCacheSource Wrapper Type —

fileprivate protocol MemoryManageable: AnyObject {
    func retain()
    func release()
}

/// A wrapper that helps us determine whether any external client code is actually using / retaining the Source. If the Source has a value, it will retain its own reference to hold in in cache. If it doesn't have a value, it will be removed when no external code is holding a reference to it. (If external code is holding a reference to it, then we should keep it in the cache dictionary, because that client code may set a value for the cache item!)
fileprivate class WeakCacheSource: MemoryManageable {
    private var strongReference: AnySource<CachedItem>?
    var source: AnySource<CachedItem>?
    var isReleased: Bool { source == nil }
    init(updateClosure: @escaping () -> Void) {
        let cacheSource = CachePersistenceSource(memory: self, updateClosure: updateClosure).eraseToAnySource()
        self.source = cacheSource
        self.strongReference = cacheSource
    }
    func retain() {
        strongReference = source
    }
    func release() {
        strongReference = nil
    }
}


// MARK: - CachePersistence Configuration-Based Extensions -

public extension CachePersistence where Options == WithMaxSize {
    var maxSize: Int {
        get { _maxSize ?? 0 }
        set {
            _maxSize = newValue
            adjustSize()
        }
    }

    var currentSize: Int {
        get { _currentSize }
    }

    func persistableSource<Value: CacheSizeRepresentable>(for descriptor: CacheDescriptor) -> AnySource<Persistable<Value>> {
        retrieve(descriptor).map { $0.asPersistable() }
    }
}

public extension CachePersistence where Options == WithMaxSizeAndMaxCount {
    var maxSize: Int {
        get { _maxSize ?? 0 }
        set {
            _maxSize = newValue
            adjustSize()
        }
    }

    var currentSize: Int {
        get { _currentSize }
    }

    var maxCount: Int {
        get { _maxCount ?? 0 }
        set {
            _maxCount = newValue
            adjustCount()
        }
    }

    var currentCount: Int {
        _currentCount
    }

    func persistableSource<Value: CacheSizeRepresentable>(for descriptor: CacheDescriptor) -> AnySource<Persistable<Value>> {
        retrieve(descriptor).map { $0.asPersistable() }
    }
}

public extension CachePersistence where Options == WithMaxCount {
    var maxCount: Int {
        get { _maxCount ?? 0 }
        set {
            _maxCount = newValue
            adjustCount()
        }
    }

    var currentCount: Int {
        _currentCount
    }

    func persistableSource<Value>(for descriptor: CacheDescriptor) -> AnySource<Persistable<Value>> {
        return retrieve(descriptor).map { $0.asPersistable() }
    }
}

public extension CachePersistence where Options == WithUnlimitedSizeAndCount {
    func persistableSource<Value>(for descriptor: CacheDescriptor) -> AnySource<Persistable<Value>> {
        retrieve(descriptor).map { $0.asPersistable() }
    }
}


// MARK: - CacheItem Model stored by CachePersistence Source -

private struct CachedItem {
    let value: Any?
    let size: Int?
    let retentionPolicy: CacheDescriptor.CacheRetentionPolicy
    let expireAfter: TimeInterval?
    let dateLastSet: Date
    let isExpired: Bool
    let set: Action<CachedItem>
    let clear: Action<Void>
}

extension CachedItem {
    func asPersistable<Value>() -> Persistable<Value> {
        if let value = value as? Value {
            return .found(.init(value: value, isExpired: isExpired, set: set.map {
                .init(value: $0, size: nil, retentionPolicy: retentionPolicy, expireAfter: expireAfter, dateLastSet: Date(), isExpired: isExpired, set: set, clear: clear)
            }, clear: clear))
        }
        return .notFound(.init(set: set.map { .init(value: $0, size: nil, retentionPolicy: retentionPolicy, expireAfter: expireAfter, dateLastSet: Date(), isExpired: isExpired, set: set, clear: clear) } ))
    }

    func asPersistable<Value: CacheSizeRepresentable>() -> Persistable<Value> {
        if let value = value as? Value {
            return .found(.init(value: value, isExpired: isExpired, set: set.map {
                .init(value: $0, size: $0.cacheSize, retentionPolicy: retentionPolicy, expireAfter: expireAfter, dateLastSet: Date(), isExpired: isExpired, set: set, clear: clear)
            }, clear: clear))
        }
        return .notFound(.init(set: set.map { .init(value: $0, size: $0.cacheSize, retentionPolicy: retentionPolicy, expireAfter: expireAfter, dateLastSet: Date(), isExpired: isExpired, set: set, clear: clear) } ))
    }
}


// MARK: - CachePersistence Source -

/// The Source that manages each cached value. If multiple client sites are using the same Cached item, they will have a reference to the same Source and get updates when the value is changed from other client code, etc.
fileprivate final class CachePersistenceSource: Source<CachedItem> {

    @ActionFromMethod(set) var setAction
    @ActionFromMethod(clear) var clearAction
    var expireWorkItem: DispatchWorkItem?

    let updateClosure: () -> Void
    weak var memory: MemoryManageable?

    lazy var initialState: CachedItem = { [unowned self] in
        return CachedItem(value: nil, size: nil, retentionPolicy: .discardUnderMemoryPressure, expireAfter: nil, dateLastSet: Date(), isExpired: true, set: self.setAction, clear: self.clearAction)
    }()

    init(memory: MemoryManageable, updateClosure: @escaping () -> Void) {
        self.memory = memory
        self.updateClosure = updateClosure
    }

    func set(_ cachedItem: CachedItem) {
        memory?.retain()
        if cachedItem.size != nil { updateClosure() }
        let cachedDate = Date()
        let isExpired = cachedItem.expireAfter.flatMap { expireAfter in
            expireWorkItem?.cancel()
            expireWorkItem = .init { [weak self] in
                guard let self = self else { return }
                self.state = .init(value: self.state.value, size: self.state.size, retentionPolicy: self.state.retentionPolicy, expireAfter: self.state.expireAfter, dateLastSet: Date(), isExpired: true, set: self.state.set, clear: self.state.clear)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + expireAfter, execute: expireWorkItem!)
            return cachedDate.distance(to: Date()) < expireAfter
        } ?? false

        state = .init(value: cachedItem.value, size: cachedItem.size, retentionPolicy: cachedItem.retentionPolicy, expireAfter: nil, dateLastSet: Date(), isExpired: isExpired, set: setAction, clear: clearAction)
    }

    func clear() {
        memory?.release()
        updateClosure()
        state = .init(value: nil, size: nil, retentionPolicy: state.retentionPolicy, expireAfter: state.expireAfter, dateLastSet: Date(), isExpired: state.isExpired, set: state.set, clear: state.clear)
    }
}


// MARK: - Protocol Static Member Extensions -

public extension CachePersistenceOptions where Self == WithMaxSize {
    static func withMaxSize(_ maxSize: Int) -> WithMaxSize {
        .init(maxSize: maxSize)
    }
}

public extension CachePersistenceOptions where Self == WithMaxCount {
    static func withMaxCount(_ maxCount: Int) -> WithMaxCount {
        .init(maxCount: maxCount)
    }
}

public extension CachePersistenceOptions where Self == WithMaxSizeAndMaxCount {
    static func withMaxSizeAndMaxCount(size: Int, count: Int) -> WithMaxSizeAndMaxCount {
        .init(maxSize: size, maxCount: count)
    }
}

public extension CachePersistenceOptions where Self == WithUnlimitedSizeAndCount {
    static var withUnlimitedSizeAndCount: WithUnlimitedSizeAndCount {
        .init()
    }
}

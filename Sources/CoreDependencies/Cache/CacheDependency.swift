//
//  CacheDependency.swift
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

/// Expresses dependency on a Caching mechanism that can return an updating Source of a Persistable<Value> for a specified CacheResource
public protocol CacheDependency {
    func cacheResource<T: CacheResource>(_ resource: T) -> Source<Persistable<T.Value>>
    func cacheResourceElement<T: ResourceElement>(_ resource: T) -> Source<Persistable<T.Value>> where T.ParentResource: CacheResource
}

public extension CoreDependencies {
    // NOTE: To get Redux-like ability to recreate app state for a given moment, an app should make all CacheResource Values Codable, and the provider should be implemented to serialize / deserialize all cache contents on demand.
    /// A concrete cache implementation. It keeps a dictionary that associates cache identifiers with Sources of Persisted<Value>s. Since Sources are reference types, changing the value of a Persisted<Value> for a particular identifier results in an update everywhere that Source is observed.
    class Cache: CacheDependency {
        private var cache = AtomicCollection<String, AnyObject>()
        private var cacheResourceElements = WeakAtomicCollection<String, AnyObject>()
        
        public init() {}
        public func cacheResource<T: CacheResource>(_ resource: T) -> Source<Persistable<T.Value>> {
            cache[resource.cacheIdentifier] {
                CacheResourceSource(resource: resource)
            }
        }
        
        public func cacheResourceElement<T: ResourceElement>(_ resource: T) -> Source<Persistable<T.Value>> where T.ParentResource: CacheResource {
            let cacheSource: Source<Persistable<T.ParentResource.Value>> = cache[resource.parentResource.cacheIdentifier] {
                CacheResourceSource(resource: resource.parentResource)
            }
            defer { cacheResourceElements.prune() }
            return cacheResourceElements[resource.elementIdentifier] {
                CacheResourceElementSource(resource: resource, cacheSource: cacheSource)
            }
        }
    }
    
    private final class CacheResourceSource<Resource: CacheResource>: Source<Persistable<Resource.Value>>, ActionSource {
        
        struct Actions: ActionMethods {
            fileprivate var set = ActionMethod(CacheResourceSource.set)
            fileprivate var clear = ActionMethod(CacheResourceSource.clear)
        }
        
        private struct MutableProperties {
            var cachedValue: Resource.Value?
            var expiredWorkItem: DispatchWorkItem?
        }
        
        private let resource: Resource
        private let state: MutableState<MutableProperties>
        
        init(resource: Resource) {
            self.resource = resource
            state = .init(mutableProperties: .init()) { state in
                return Persistable<Resource.Value>.notFound(.init(error: nil, set: state.action(\.set)))
            }
            super.init(state)
        }
        
        private func set(value: Resource.Value) {
            let timestamp = Date.timeIntervalSinceReferenceDate
            state.expiredWorkItem?.cancel()
            state.cachedValue = value
            var isExpired = { false }
            if let expireAfter = resource.expireCacheAfter {
                isExpired = { expireAfter < Date.timeIntervalSinceReferenceDate - timestamp }
                // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if case .found(let found) = self.model, found.isExpired {
                        self.state.setModel(.found(found))
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + expireAfter, execute: workItem)
                state.expiredWorkItem = workItem
            }
            state.setModel(.found(.init(value: value, isExpired: isExpired, set: self.state.action(\.set), clear: self.state.action(\.clear))))
        }
        
        private func clear() {
            state.cachedValue = nil
            state.expiredWorkItem?.cancel()
            state.setModel(.notFound(.init(error: nil, set: state.action(\.set))))
        }
    }
    
    private final class CacheResourceElementSource<Resource: ResourceElement>: Source<Persistable<Resource.Value>>, ActionSource where Resource.ParentResource: CacheResource {
        
        struct Actions: ActionMethods {
            fileprivate var set = ActionMethod(CacheResourceElementSource.set)
            fileprivate var clear = ActionMethod(CacheResourceElementSource.clear)
        }
        
        private let resource: Resource
        private let state: State
        private let cacheSource: Source<Persistable<Resource.ParentResource.Value>>
        init(resource: Resource, cacheSource: Source<Persistable<Resource.ParentResource.Value>>) {
            self.resource = resource
            self.cacheSource = cacheSource
            state = .init { state in .notFound(.init(error: nil, set: state.action(\.set))) }
            super.init(state)
            switch cacheSource.model {
            case .found(let found):
                do {
                    guard let value = try resource.getElement(from: found.value) else {
                        state.setModel(.notFound(.init(set: state.action(\.set))))
                        return
                    }
                    state.setModel(.found(.init(value: value, isExpired: { found.isExpired }, set: state.action(\.set), clear: state.action(\.clear))))
                } catch {
                    state.setModel(.notFound(.init(error: error, set: state.action(\.set))))
                }
            case .notFound:
                state.setModel(.notFound(.init(set: state.action(\.set))))
            }
        }
        
        private func set(value: Resource.Value) {
            let cacheValue: Resource.ParentResource.Value?
            switch cacheSource.model {
            case .notFound:
                cacheValue = nil
            case .found(let found):
                cacheValue = found.value
            }
            
            let closure = resource.set(element: value)
            
            do {
                let parentValue = try closure(cacheValue)
                let cacheSource = cacheSource
                state.setModel(.found(.init(value: value, isExpired: { cacheSource.model.found?.isExpired == true }, set: state.action(\.set), clear: state.action(\.clear))))
                try? cacheSource.model.set(parentValue)
            } catch {
                state.setModel(.notFound(.init(error: error, set: state.action(\.set))))
            }
        }
        
        private func clear() {
            let cacheValue: Resource.ParentResource.Value?
            switch cacheSource.model {
            case .notFound:
                cacheValue = nil
            case .found(let found):
                cacheValue = found.value
            }
            
            let closure = resource.set(element: nil)
            
            do {
                let value = try closure(cacheValue)
                state.setModel(.notFound(.init(set: state.action(\.set))))
                try? cacheSource.model.set(value)
            } catch {
                state.setModel(.notFound(.init(set: state.action(\.set))))
            }
        }
    }
}

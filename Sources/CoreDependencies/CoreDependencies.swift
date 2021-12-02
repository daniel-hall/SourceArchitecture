//
//  CoreDependencies.swift
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

// TODO: Add Keychain Dependency implementation when it has been created
/// A container that holds the core dependencies necessary for creating or mocking any Source or data in the app. It also conforms to all the core dependency protocols, allowing it to be passed around as the dependency for any Source. By default, it is initialized with the framework-provided implementations of the different dependencies, but app-specific implementations can be passed in.
public struct CoreDependencies: CacheDependency, NetworkDependency, FileDependency, UserDefaultsDependency {
    private let network: NetworkDependency
    private let cache: CacheDependency
    private let userDefaults: UserDefaultsDependency
    private let file: FileDependency
    
    public init(network: NetworkDependency = Network(), cache: CacheDependency = Cache(), userDefaults: UserDefaultsDependency = UserDefaults(), file: FileDependency = File()) {
        self.network = network
        self.cache = cache
        self.userDefaults = userDefaults
        self.file = file
    }
    
    public func networkResource<T>(_ resource: T) -> Source<Fetchable<T.Value>> where T : NetworkResource {
        network.networkResource(resource)
    }
    
    public func fileResource<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : FileResource {
        file.fileResource(resource)
    }
    
    public func fileResourceElement<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : ResourceElement, T.ParentResource : FileResource {
        file.fileResourceElement(resource)
    }
    
    public func cacheResource<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : CacheResource {
        cache.cacheResource(resource)
    }
    
    public func cacheResourceElement<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : ResourceElement, T.ParentResource : CacheResource {
        cache.cacheResourceElement(resource)
    }
    
    public func userDefaultsResource<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : UserDefaultsResource {
        userDefaults.userDefaultsResource(resource)
    }
    
    public func userDefaultsResourceElement<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : ResourceElement, T.ParentResource : UserDefaultsResource {
        userDefaults.userDefaultsResourceElement(resource)
    }
}

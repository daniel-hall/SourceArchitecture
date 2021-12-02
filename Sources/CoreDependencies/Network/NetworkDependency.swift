//
//  NetworkDependency.swift
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

/// Expresses dependency on a Network  (e.g. a local network or the internet) that can return an updating Source of a Fetchable<Value> for a specified NetworkResource
public protocol NetworkDependency {
    func networkResource<T: NetworkResource>(_ resource: T) -> Source<Fetchable<T.Value>>
}

public extension NetworkDependency where Self: CacheDependency {
    func cachedNetworkResource<T: NetworkResource & CacheResource>(_ resource: T) -> Source<Fetchable<T.Value>> {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: cacheResource(resource))
    }
    
    func cachedNetworkResource<T: NetworkResource & ResourceElement>(_ resource: T) -> Source<Fetchable<T.Value>> where T.ParentResource: CacheResource {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: cacheResourceElement(resource))
    }
}

public extension NetworkDependency where Self: UserDefaultsDependency {
    func userDefaultsPersistedNetworkResource<T: NetworkResource & UserDefaultsResource>(_ resource: T) -> Source<Fetchable<T.Value>> {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: userDefaultsResource(resource))
    }
    
    func userDefaultsPersistedNetworkResource<T: NetworkResource & ResourceElement>(_ resource: T) -> Source<Fetchable<T.Value>> where T.ParentResource: UserDefaultsResource {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: userDefaultsResourceElement(resource))
    }
}

public extension NetworkDependency where Self: FileDependency {
    func filePersistedNetworkResource<T: NetworkResource & FileResource>(_ resource: T) -> Source<Fetchable<T.Value>> {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: fileResource(resource))
    }
    
    func filePersistedNetworkResource<T: NetworkResource & ResourceElement>(_ resource: T) -> Source<Fetchable<T.Value>> where T.ParentResource: FileResource {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: fileResourceElement(resource))
    }
}

public extension NetworkDependency where Self: KeychainDependency {
    func keychainPersistedNetworkResource<T: NetworkResource & KeychainResource>(_ resource: T) -> Source<Fetchable<T.Value>> {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: keychainResource(resource))
    }
    
    func keychainPersistedNetworkResource<T: NetworkResource & ResourceElement>(_ resource: T) -> Source<Fetchable<T.Value>> where T.ParentResource: KeychainResource {
        PersistedFetchedSource(fetchedSource: networkResource(resource), persistedSource: keychainResourceElement(resource))
    }
}


public extension CoreDependencies {
    fileprivate class MissingURLErrorSource<Value>: Source<Fetchable<Value>>, ActionSource {
        struct Actions: ActionMethods {
            var retry = ActionMethod(MissingURLErrorSource.retry)
        }
        struct MutableProperties {
            var failedAttempts = 1
        }
        let state: MutableState<MutableProperties>
        init() {
            state = .init(mutableProperties: .init()) { state in .failure(.init(error: CoreDependencies.Network.Error.missingURL, failedAttempts: state.failedAttempts, retry: state.action(\.retry))) }
            super.init(state)
        }
        
        private func retry() {
            state.failedAttempts = state.failedAttempts + 1
            state.setModel(.failure(.init(error: CoreDependencies.Network.Error.missingURL, failedAttempts: state.failedAttempts, retry: state.action(\.retry))))
        }
    }
    
    class Network: NetworkDependency {
        
        public enum Error: LocalizedError {
            case missingURL
            case missingDataOrResponse
            case timedOut
            
            public var errorDescription: String? {
                switch self {
                case .missingURL: return "The provided NetworkResource's URLRequest does not have a URL"
                case .missingDataOrResponse: return "Network request finished but was missing either data or response object"
                case .timedOut: return "The network request timed out"
                }
            }
        }
        
        private let urlSession: URLSession
        private let sources = WeakAtomicCollection<URL, AnyObject>()
        
        public init(urlSession: URLSession? = nil) {
            self.urlSession = urlSession ?? {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.allowsCellularAccess = true
                configuration.httpMaximumConnectionsPerHost = 2
                configuration.allowsConstrainedNetworkAccess = true
                return URLSession(configuration: configuration)
            }()
        }
        
        
        public func networkResource<T>(_ resource: T) -> Source<Fetchable<T.Value>> where T : NetworkResource {
            guard let url = resource.networkURLRequest.url else {
                return MissingURLErrorSource()
            }
            let source: URLSessionNetworkResourceSource = sources[url] {
                return URLSessionNetworkResourceSource(resource) { self.urlSession }
            }
            switch source.model {
            case .fetched(let fetched): try? fetched.refresh()
            default: source.fetch()
            }
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.sources.prune()
            }
            return source
        }
    }
    
    private final class URLSessionNetworkResourceSource<Resource: NetworkResource>: Source<Fetchable<Resource.Value>>, ActionSource {
        
        struct Actions: ActionMethods {
            fileprivate var fetch = ActionMethod(URLSessionNetworkResourceSource.fetch)
            fileprivate var refresh = ActionMethod(URLSessionNetworkResourceSource.refresh)
            fileprivate var retry = ActionMethod(URLSessionNetworkResourceSource.retry)
        }
        
        fileprivate struct MutableProperties {
            var dataTask: URLSessionDataTask?
            var failedAttempts = 0
            var timeoutWorkItem: DispatchWorkItem?
            var isCancelled = false
        }
        private let state: MutableState<MutableProperties>
        private let resource: Resource
        private let urlSession: () -> URLSession
        
        init(_ resource: Resource, urlSession: @escaping () -> URLSession) {
            self.resource = resource
            self.urlSession = urlSession
            state = .init(mutableProperties: .init(), model: .fetching(.init(progress: nil)))
            super.init(state)
        }
        
        fileprivate func fetch() {
            let progress = sendRequest()
            self.state.setModel(.fetching(.init(progress: ProgressSource(progress: progress))))
        }
        
        fileprivate func retry() {
            fetch()
        }
        
        private func refresh()  {
            _ = sendRequest()
        }
        
        func sendRequest() -> Foundation.Progress {
            let dataTask = urlSession().dataTask(with: resource.networkURLRequest) { [weak self] data, response, error in
                guard let self = self else { return }
                guard !self.state.isCancelled else { return }
                if let data = data, let response = response, error == nil {
                    do {
                        let value = try self.resource.transform(networkResponse: self.resource.decode(data: data, response: response))
                        self.state.timeoutWorkItem?.cancel()
                        self.state.failedAttempts = 0
                        if self.state.isCancelled { return }
                        self.state.setModel(.fetched(.init(value: value, refresh: self.state.action(\.refresh))))
                    } catch {
                        self.state.failedAttempts += 1
                        self.state.timeoutWorkItem?.cancel()
                        if self.state.isCancelled { return }
                        self.state.setModel(.failure(.init(error: error, failedAttempts: self.state.failedAttempts, retry: self.state.action(\.retry))))
                    }
                } else {
                    let error = error ?? CoreDependencies.Network.Error.missingDataOrResponse
                    self.state.failedAttempts += 1
                    self.state.timeoutWorkItem?.cancel()
                    if self.state.isCancelled { return }
                    self.state.setModel(.failure(.init(error: error, failedAttempts: self.state.failedAttempts, retry: self.state.action(\.retry))))
                }
            }
            state.isCancelled = true
            state.dataTask?.cancel()
            state.timeoutWorkItem?.cancel()
            resource.networkRequestTimeout.map {
                let timeoutWorkItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if case .fetching = self.model {
                        self.state.failedAttempts += 1
                        self.state.isCancelled = true
                        self.state.dataTask?.cancel()
                        self.state.setModel(.failure(.init(error: CoreDependencies.Network.Error.timedOut, failedAttempts: self.state.failedAttempts, retry: self.state.action(\.retry))))
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + $0, execute: timeoutWorkItem)
                state.timeoutWorkItem = timeoutWorkItem
            }
            state.isCancelled = false
            state.dataTask = dataTask
            dataTask.resume()
            return dataTask.progress
        }
        
        deinit {
            state.isCancelled = true
            state.dataTask?.cancel()
            state.timeoutWorkItem?.cancel()
        }
    }
}

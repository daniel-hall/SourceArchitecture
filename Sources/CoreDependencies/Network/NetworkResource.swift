//
//  NetworkResource.swift
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


/// A protocol for describing a resource that is retrieved over the network
public protocol NetworkResource: Resource {
    associatedtype NetworkResponse
    associatedtype Value = NetworkResponse
    
    var networkURLRequest: URLRequest { get }
    var networkRequestTimeout: TimeInterval? { get }
    func decode(data: Data, response: URLResponse) throws -> NetworkResponse
    func transform(networkResponse: NetworkResponse) throws -> Value
}

public extension NetworkResource {
    var networkRequestTimeout: TimeInterval? { nil }
    
}

/// A default implementation for decoding a NetworkResponse if it conforms to Decodable
public extension NetworkResource where NetworkResponse: Decodable {
    func decode(data: Data, response: URLResponse) throws -> NetworkResponse {
        try JSONDecoder().decode(NetworkResponse.self, from: data)
    }
}

/// A default identity implementation for when the NetworkResponse _is_ the Resource Value
public extension NetworkResource where Value == NetworkResponse {
    func transform(networkResponse: NetworkResponse) throws -> Value {
        return networkResponse
    }
}

public extension NetworkResource {
    /// Allows transforming a NetworkResource that already returns a given Value into a NetworkResource that returns a different Value
    func map<NewValue>(_ transform: @escaping (NetworkResponse) throws -> NewValue) -> AnyNetworkResource<NewValue> {
        AnyNetworkResource(self, transform: transform)
    }
}

/// A concrete type eraser for a NetworkResource.  Allows APIs to pass around a NetworkResource (analogous to a specific network request) without a concrete type, but which results in a known decoded value when used
public struct AnyNetworkResource<Value>: NetworkResource {
    public typealias NetworkResponse = Value
    public var networkURLRequest: URLRequest { urlRequestClosure() }
    private let urlRequestClosure: () -> URLRequest
    private let decodeClosure: (Data, URLResponse) throws -> NetworkResponse
    
    fileprivate init<T: NetworkResource>(_ resource: T, transform: @escaping (T.NetworkResponse) throws -> NetworkResponse) {
        urlRequestClosure = { resource.networkURLRequest }
        decodeClosure = { try transform(resource.decode(data: $0, response: $1)) }
    }
    
    public init<T: NetworkResource>(_ resource: T) where T.NetworkResponse == NetworkResponse, T.Value == Value {
        urlRequestClosure = { resource.networkURLRequest }
        decodeClosure = resource.decode
    }
    
    public func decode(data: Data, response: URLResponse) throws -> NetworkResponse {
        try decodeClosure(data, response)
    }
}

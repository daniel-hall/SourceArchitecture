//
//  ResourceDecorator.swift
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

public protocol ResourceDecorator {
    associatedtype DecoratedResource: Resource
    var decoratedResource: DecoratedResource { get }
}

public extension ResourceDecorator {
    typealias Value = DecoratedResource.Value
}

public extension DecodableResource where Self: ResourceDecorator, DecoratedResource: DecodableResource {
    func decode(_ data: Data) throws -> DecoratedResource.Value {
        try decoratedResource.decode(data)
    }
}

public extension EncodableResource where Self: ResourceDecorator, DecoratedResource: EncodableResource {
    func encode(_ value: DecoratedResource.Value) throws -> Data {
        try decoratedResource.encode(value)
    }
}

public extension ResourceDecorator where DecoratedResource: ResourceElement {
    typealias ParentResource = DecoratedResource.ParentResource
}

public extension ResourceElement where Self: ResourceDecorator, DecoratedResource: ResourceElement {
    var parentResource: DecoratedResource.ParentResource { decoratedResource.parentResource }
    var elementIdentifier: String { decoratedResource.elementIdentifier }
    func set(element: DecoratedResource.Value?) -> (DecoratedResource.ParentResource.Value?) throws -> DecoratedResource.ParentResource.Value {
        decoratedResource.set(element: element)
    }
    func getElement(from value: DecoratedResource.ParentResource.Value) throws -> DecoratedResource.Value? {
        try decoratedResource.getElement(from: value)
    }
}

public extension ResourceDecorator where DecoratedResource: NetworkResource {
    typealias NetworkResponse = DecoratedResource.NetworkResponse
}

public extension NetworkResource where Self: ResourceDecorator, DecoratedResource: NetworkResource {
    
    var networkURLRequest: URLRequest {
        decoratedResource.networkURLRequest
    }
    
    var networkRequestTimeout: TimeInterval? {
        decoratedResource.networkRequestTimeout
    }
    
    func decode(data: Data, response: URLResponse) throws -> DecoratedResource.NetworkResponse {
        try decoratedResource.decode(data: data, response: response)
    }
    func transform(networkResponse: DecoratedResource.NetworkResponse) throws -> DecoratedResource.Value {
        try decoratedResource.transform(networkResponse: networkResponse)
    }
}

public extension CacheResource where Self: ResourceDecorator, DecoratedResource: CacheResource {
    var expireCacheAfter: TimeInterval? { decoratedResource.expireCacheAfter }
    var cacheIdentifier: String { decoratedResource.cacheIdentifier }
}

public extension UserDefaultsResource where Self: ResourceDecorator, DecoratedResource: UserDefaultsResource {
    var expireUserDefaultsAfter: TimeInterval? { decoratedResource.expireUserDefaultsAfter }
    var userDefaultsIdentifier: String { decoratedResource.userDefaultsIdentifier }
}

public extension FileResource where Self: ResourceDecorator, DecoratedResource: FileResource {
    var expireFileAfter: TimeInterval? { decoratedResource.expireFileAfter }
    var fileDirectory: FileManager.SearchPathDirectory { decoratedResource.fileDirectory }
    var fileDomainMask: FileManager.SearchPathDomainMask { decoratedResource.fileDomainMask }
    var filePath: String { decoratedResource.filePath }
    var fileURL: URL { decoratedResource.fileURL }
}

public extension KeychainResource where Self: ResourceDecorator, DecoratedResource: KeychainResource {
    var expireKeychainAfter: TimeInterval? { decoratedResource.expireKeychainAfter }
    var keychainAccount: String { decoratedResource.keychainAccount }
    var keychainService: String { decoratedResource.keychainService }
    var keychainAccessControl: KeychainResourceAccessControl { decoratedResource.keychainAccessControl }
}

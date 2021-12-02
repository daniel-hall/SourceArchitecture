//
//  Resource.swift
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


public protocol Resource {
    associatedtype Value
}

public protocol EncodableResource: Resource {
    func encode(_ value: Value) throws -> Data
}

/// A default implementation for encoding an EncodableResource's Value if it conforms to Encodable
public extension EncodableResource where Value: Encodable {
    func encode(_ value: Value) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

public protocol DecodableResource: Resource {
    func decode(_ data: Data) throws -> Value
}

/// A default implementation for decoding a DecodableResource's Value if it conforms to Decodable
public extension DecodableResource where Value: Decodable {
    func decode(_ data: Data) throws -> Value {
        try JSONDecoder().decode(Value.self, from: data)
    }
}

/// Protocol for representing a Resource that is a part of a larger Resource. For example, a single value from a FileResource that persists hundreds of values. This allows a cleaner organization of resources such as a cached dictionary of prices rather than hundreds or thousands of individually cached prices.
public protocol ResourceElement: Resource {
    associatedtype ParentResource: Resource
    var parentResource: ParentResource { get }
    var elementIdentifier: String { get }
    func set(element: Value?) -> (ParentResource.Value?) throws -> ParentResource.Value
    func getElement(from value: ParentResource.Value) throws -> Value?
}







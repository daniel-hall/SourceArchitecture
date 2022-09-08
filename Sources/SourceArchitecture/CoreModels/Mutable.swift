//
//  Mutable.swift
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


@dynamicMemberLookup
/// A Model that contains a value and an action to set a new value
public struct Mutable<Value> {
    public let value: Value
    public let set: Action<Value>
    public init(value: Value, set: Action<Value>) {
        self.value = value
        self.set = set
    }
    public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
        value[keyPath: keyPath]
    }
}

extension Mutable: Equatable where Value: Equatable {
    public static func ==(lhs: Mutable<Value>, rhs: Mutable<Value>) -> Bool {
        lhs.value == rhs.value
    }
}

extension Mutable: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        value.hash(into: &hasher)
    }
}

extension Mutable: Identifiable where Value: Identifiable {
    public var id: Value.ID { value.id }
}

public protocol MutableRepresentable {
    associatedtype Value
    func asMutable() -> Mutable<Value>
}

extension Mutable: MutableRepresentable {
    public func asMutable() -> Mutable<Value> {
        return self
    }
}

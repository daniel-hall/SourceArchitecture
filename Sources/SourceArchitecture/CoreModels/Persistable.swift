//
//  Persistable.swift
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

/// A Model for a Value that is persisted somewhere (cache, disk, database, user defaults, etc.) A PersistedModel value may have an expiration time or other expiration condition placed upon it.
public enum Persistable<Value> {
    case found(Found)
    case notFound(NotFound)
    
    public var set: Action<Value> {
        switch self {
        case .found(let found): return found.set
        case .notFound(let notFound): return notFound.set
        }
    }
    
    public var clear: Action<Void>? {
        found?.clear
    }
    
    public var found: Found? {
        if case .found(let found) = self { return found }
        return nil
    }
    
    public var notFound: NotFound? {
        if case .notFound(let notFound) = self { return notFound }
        return nil
    }
    
    @dynamicMemberLookup
    public struct Found {
        public let set: Action<Value>
        public let clear: Action<Void>
        public var isExpired: Bool { isExpiredClosure() }
        public let value: Value
        private let isExpiredClosure: () -> Bool
        
        public init(value: Value, isExpired: @escaping () -> Bool, set: Action<Value>, clear: Action<Void>) {
            self.value = value
            self.isExpiredClosure = isExpired
            self.set = set
            self.clear = clear
        }
        
        public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
            value[keyPath: keyPath]
        }
        
        public subscript<T, V>(dynamicMember keyPath: KeyPath<V, T>) -> T? where Value == Optional<V> {
            value?[keyPath: keyPath]
        }
    }
    
    public struct NotFound {
        public let error: Error?
        public let set: Action<Value>
        public init(error: Error? = nil, set: Action<Value>) {
            self.error = error
            self.set = set
        }
    }
}

extension Persistable: PersistableRepresentable {
    public func asPersistable() -> Persistable<Value> {
        return self
    }
}

extension Persistable: Equatable where Value: Equatable {
    public static func ==(lhs: Persistable<Value>, rhs: Persistable<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound): return true
        case (.found(let left), .found(let right)):
            return left.value == right.value
            && left.isExpired == right.isExpired
        default: return false
        }
    }
}

public protocol PersistableRepresentable {
    associatedtype Value
    func asPersistable() -> Persistable<Value>
}

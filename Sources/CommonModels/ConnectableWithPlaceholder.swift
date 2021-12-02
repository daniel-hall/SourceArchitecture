//
//  ConnectableWithPlaceholder.swift
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


public enum ConnectableWithPlaceholder<Value, Placeholder> {
    case connected(Connected)
    case disconnected(Disconnected)

    @dynamicMemberLookup
    public struct Connected {
        public let disconnect: Action<Void>
        public let value: Value
        public let placeholder: Placeholder

        public init(placeholder: Placeholder, value: Value, disconnect: Action<Void>) {
            self.value = value
            self.disconnect = disconnect
            self.placeholder = placeholder
        }

        public subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
            value[keyPath: keyPath]
        }

        public subscript<T, V>(dynamicMember keyPath: KeyPath<V, T>) -> T? where Value == Optional<V> {
            value?[keyPath: keyPath]
        }
    }

    public struct Disconnected {
        public let connect: Action<Void>
        public let placeholder: Placeholder

        public init(placeholder: Placeholder, connect: Action<Void>) {
            self.connect = connect
            self.placeholder = placeholder
        }
    }

    public var connected: Connected? {
        if case .connected(let connected) = self {
            return connected
        }
        return nil
    }

    public var disconnected: Disconnected? {
        if case .disconnected(let disconnected) = self {
            return disconnected
        }
        return nil
    }

    public var isConnected: Bool {
        connected != nil
    }

    public var placeholder: Placeholder {
        switch self {
        case .connected(let connected): return connected.placeholder
        case .disconnected(let disconnected): return disconnected.placeholder
        }
    }

    public func connect() throws {
        try disconnected?.connect()
    }

    public func disconnect() throws {
        try connected?.disconnect()
    }
}

public extension ConnectableWithPlaceholder {
    func map<NewValue>(_ transform: (Value) -> NewValue) -> ConnectableWithPlaceholder<NewValue, Placeholder> {
        switch self {
        case .connected(let connected):
            return .connected(.init(placeholder: connected.placeholder, value: transform(connected.value), disconnect: connected.disconnect))
        case .disconnected(let disconnected):
            return .disconnected(.init(placeholder: disconnected.placeholder, connect: disconnected.connect))
        }
    }

    func mapPlaceholder<NewPlaceholder>(_ transform: (Placeholder) -> NewPlaceholder) -> ConnectableWithPlaceholder<Value, NewPlaceholder> {
        switch self {
        case .connected(let connected): return .connected(.init(placeholder: transform(connected.placeholder), value: connected.value, disconnect: connected.disconnect))
        case .disconnected(let disconnected): return .disconnected(.init(placeholder: transform(disconnected.placeholder), connect: disconnected.connect))
        }
    }
}

public protocol ConnectableWithPlaceholderRepresentable {
    associatedtype Value
    associatedtype Placeholder
    func asConnectableWithPlaceholder() -> ConnectableWithPlaceholder<Value, Placeholder>
}

extension ConnectableWithPlaceholder: ConnectableWithPlaceholderRepresentable {
    public func asConnectableWithPlaceholder() -> ConnectableWithPlaceholder<Value, Placeholder> {
        self
    }
}

extension ConnectableWithPlaceholder: ConnectableRepresentable {
    public func asConnectable() -> Connectable<Value> {
        switch self {
        case .disconnected(let disconnected): return .disconnected(.init(connect: disconnected.connect))
        case .connected(let connected): return .connected(.init(value: connected.value, disconnect: connected.disconnect))
        }
    }
}

extension ConnectableWithPlaceholder: Identifiable where Placeholder: Identifiable {
    public var id: Placeholder.ID { placeholder.id }
}


extension ConnectableWithPlaceholder: HasEqualPlaceholder where Placeholder: Equatable {
    func hasEqualPlaceholder(_ other: Any?) -> Bool {
        self.placeholder == (other as? Placeholder)
    }
}

extension ConnectableWithPlaceholder: Equatable where Value: Equatable {
    fileprivate func placeholderIsEqual(to other: Placeholder?) -> Bool {
        (placeholder is Void) || (self as? HasEqualPlaceholder)?.hasEqualPlaceholder(other) == true
    }
    public static func ==(lhs: ConnectableWithPlaceholder<Value, Placeholder>, rhs: ConnectableWithPlaceholder<Value, Placeholder>) -> Bool {
        switch (lhs, rhs) {
        case (.connected(let left), .connected(let right)):
            return lhs.placeholderIsEqual(to: rhs.placeholder)
            && left.value == right.value
        case (.disconnected, .disconnected):
            return lhs.placeholderIsEqual(to: rhs.placeholder)
        default: return false
        }
    }
}

public extension Source where Model: ConnectableRepresentable {
    func addingPlaceholder<T>(_ placeholder: T) -> Source<ConnectableWithPlaceholder<Model.Value, T>> {
        map { $0.asConnectable().addingPlaceholder(placeholder)}
    }
}

public extension Source where Model: ConnectableWithPlaceholderRepresentable {
    func mapConnectedValue<NewValue>(_ transform: @escaping (Model.Value) -> (NewValue)) -> Source<ConnectableWithPlaceholder<NewValue, Model.Placeholder>> {
        map { $0.asConnectableWithPlaceholder().map(transform) }
    }

    func mapConnectablePlaceholder<NewPlaceholder>(_ transform: @escaping (Model.Placeholder) -> (NewPlaceholder)) -> Source<ConnectableWithPlaceholder<Model.Value, NewPlaceholder>> {
        map { $0.asConnectableWithPlaceholder().mapPlaceholder(transform)}
    }
}

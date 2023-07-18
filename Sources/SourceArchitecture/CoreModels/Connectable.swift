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


/// A `Connectable<Value>` represents a value that doesn't materialize until it is needed (when `connect()` is called) and which can be discarded when not needed (when `disconnect()` is called). This is good for modeling deferred work which can produce a value, but only at the time it is needed. It is particularly important for values rendered by SwiftUI Lists and and similar views. These views will hold and retain any model or value they are initialized with even if not on screen. So for thousands of rows in a SwiftUI List, there will be thousands of items (possibly all updating in the background!) held in memory even if there are only 10 cells actually visible and being rendered. By implementing these SwiftUI cells / rows with a `Connectable<Model>`, each one of them can use `.onAppear { model.connect() }` and `.onDisappear { model.disconnect() }` to only load and hold values when the view is actually visible, and release the value (discontinuing any updates or logic) and free its memory when the view is no longer visible.
public enum Connectable<Value> {
    case connected(Connected)
    case disconnected(Disconnected)
    
    public struct Connected {
        public let disconnect: Action<Void>
        public let value: Value
        
        public init(value: Value, disconnect: Action<Void>) {
            self.value = value
            self.disconnect = disconnect
        }
    }
    
    public struct Disconnected {
        public let connect: Action<Void>
        
        public init(connect: Action<Void>) {
            self.connect = connect
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

    /// Signals that the expected Value should be created and made available
    public func connect(ifUnavailable: ((ActionExecution) -> Bool)? = nil) {
        disconnected?.connect(ifUnavailable: ifUnavailable)
    }

    /// Release the value to free memory and cease any activity it may be performing
    public func disconnect(ifUnavailable: ((ActionExecution) -> Bool)? = nil) {
        connected?.disconnect(ifUnavailable: ifUnavailable)
    }
}


public extension Connectable {
    func addingPlaceholder<Placeholder>(_ placeholder: Placeholder) -> ConnectableWithPlaceholder<Value, Placeholder> {
        switch self {
        case .disconnected(let disconnected): return .disconnected(.init(placeholder: placeholder, connect: disconnected.connect))
        case .connected(let connected): return .connected(.init(placeholder: placeholder, value: connected.value, disconnect: connected.disconnect))
        }
    }
}

public extension Connectable {
    func map<NewValue>(_ transform: (Value) -> NewValue) -> Connectable<NewValue> {
        switch self {
        case .connected(let connected):
            return .connected(.init(value: transform(connected.value), disconnect: connected.disconnect))
        case .disconnected(let disconnected):
            return .disconnected(.init(connect: disconnected.connect))
        }
    }
}

public protocol ConnectableRepresentable {
    associatedtype Value
    func asConnectable() -> Connectable<Value>
}

extension Connectable: ConnectableRepresentable {
    public func asConnectable() -> Connectable<Value> {
        self
    }
}

extension Connectable: Equatable where Value: Equatable {
    public static func ==(lhs: Connectable<Value>, rhs: Connectable<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.connected(let left), .connected(let right)):
            return left.value == right.value
        case (.disconnected, .disconnected):
            return true
        default: return false
        }
    }
}

public extension AnySource where Model: ConnectableRepresentable {
    // Disfavored overload because if the Model is also ConnectableWithPlaceholderRepresentable, we want to prefer that version of mapConnectedValue to preserve the more complete type
    @_disfavoredOverload func mapConnectedValue<NewValue>(_ transform: @escaping (Model.Value) -> NewValue) -> AnySource<Connectable<NewValue>> {
        map { $0.asConnectable().map(transform) }
    }
}

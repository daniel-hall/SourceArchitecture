//
//  Source.swift
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
import Combine
import SwiftUI


// MARK: - Source Class & Extensions -

public final class Source<Model> {
    public typealias Model = Model
    @ModelState public var model: Model
    private var subscription: AnyCancellable?
    fileprivate init<T: ComputedSource>(_ source: T) where T.Model == Model {
        _model = source.source.$model
    }
    fileprivate init<T: CustomSourceProtocol>(_ source: T ) where T.Model == Model {
        _model = .unsafePlaceholder
        _model = .init(modelClosure: { source._model as? Model ?? source.defaultModel }, source: self, lock: source.lock)
        subscription = source.$_model.sink { [weak self] in
            if let model = $0 as? Model {
               self?._model.setModel(model)
            }
        }
    }

    internal func subscribe(_ closure: @escaping (Model) -> Void) -> AnyCancellable {
        _model.subscribe(closure)
    }

    public func subscribe<T: CustomSourceProtocol>(_ source: T, method: @escaping (T) -> (Model) -> Void, immediately: Bool = true) {
        _model.subscribe(subscriber: source, immediately: immediately) { [weak source] in
            guard let source = source else {
                return
            }
            method(source)($0)
        }
    }

    public func unsubscribe<T: CustomSourceProtocol>(_ source: T) {
        _model.unsubscribe(source)
    }
}

extension Source: Identifiable where Model: Identifiable {
    public var id: Model.ID { model.id }
}

extension Source: Equatable where Model: Equatable {
    public static func ==(lhs: Source<Model>, rhs: Source<Model>) -> Bool {
        lhs.model == rhs.model
    }
}


// MARK: - _Source Base Class -

open class _Source {
    fileprivate let lock = NSRecursiveLock()
    fileprivate var threadsafe: Any?
    @Published fileprivate var _model: Any?
    public init() { }
}


// MARK: - CustomSource Protocol & Extensions -

public typealias CustomSource = _Source & CustomSourceProtocol

public protocol CustomSourceProtocol: _Source {
    associatedtype Threadsafe: ThreadsafeProperties = NoThreadsafeProperties
    associatedtype Actions: ActionMethods = NoActions
    associatedtype Model
    var defaultModel: Model { get }
}

public extension CustomSourceProtocol {

    func eraseToSource() -> Source<Model> {
        Source(self)
    }

    var model: Model {
        get { _model as? Model ?? defaultModel }
        set { _model = newValue }
    }

    var threadsafe: SourceArchitecture.Threadsafe<Threadsafe> {
        lock.lock()
        defer { lock.unlock() }
        if (threadsafe as? SourceArchitecture.Threadsafe<Threadsafe>) == nil {
            threadsafe = SourceArchitecture.Threadsafe<Threadsafe>(lock: lock)
        }
        return threadsafe as! SourceArchitecture.Threadsafe<Threadsafe>
    }

    var actions: SourceActions<Self> {
        .init(source: self)
    }
}

fileprivate extension CustomSourceProtocol {
    func hasCurrentAction(identifier: String) -> Bool {
        hasCurrentAction(identifier: identifier, in: model)
    }

    private func hasCurrentAction(identifier: String, in model: Any) -> Bool {
        if (model as? IdentifiableAction)?.identifier == identifier { return true }
        if model is ReflectionExempt { return false }
        return Mirror(reflecting: model).children.first { hasCurrentAction(identifier: identifier, in: $0.value) } != nil ? true : false
    }
}


// MARK: - CustomSource Supporting & Associated Types -

open class ActionMethods {
    public required init() { }
}

public final class NoActions: ActionMethods { }

open class ThreadsafeProperties {
    public required init() { }
}

public final class NoThreadsafeProperties: ThreadsafeProperties { }

@dynamicMemberLookup
public final class Threadsafe<Properties: ThreadsafeProperties> {
    private let lock: NSRecursiveLock
    private var properties: Properties

    fileprivate init(lock: NSRecursiveLock) {
        self.lock = lock
        self.properties = Properties.init()
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<Properties, T>) -> T {
        lock.lock()
        defer { lock.unlock() }
        return properties[keyPath: keyPath]
    }

    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Properties, T>) -> T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return properties[keyPath: keyPath]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            properties[keyPath: keyPath] = newValue
        }
    }
}

@dynamicMemberLookup
public struct SourceActions<Source: CustomSourceProtocol> {
    fileprivate weak var source: Source?
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<Source.Actions, ActionMethod<Source, T>>) -> Action<T> {
        let actions = Source.Actions()
        let method = actions[keyPath: keyPath]
        let methodName = Mirror(reflecting: actions).children.first { ($0.value as? ActionMethod<Source, T>)?.uuid == method.uuid }!.label!
        let identifier = String(describing: Source.self) + "." + methodName
        return .init(identifier: identifier, source: source!, method: method.method)
    }
}

public struct ActionMethod<Source, Input> {
    fileprivate let uuid = UUID()
    fileprivate let method: (Source) -> (Input) -> Void
    public init(_ method: @escaping (Source) -> (Input) -> Void) {
        self.method = method
    }
    public init(_ method: @escaping (Source) -> () -> Void) where Input == Void {
        self.method = { source in { _ in method(source)() } }
    }
}


// MARK: - ComputedSource Protocol & Extensions -

public protocol ComputedSource {
    associatedtype Model
    var source: Source<Model> { get }
}

public extension ComputedSource {
    func eraseToSource() -> Source<Model> {
        Source(self)
    }
}


// MARK: - ModelState Property Wrapper & Extensions -

@propertyWrapper
public struct ModelState<Model>: DynamicProperty, ReflectionExempt {
    @ObservedObject fileprivate var value: Observable<Model?>
    fileprivate let lock: NSRecursiveLock
    private let subscriptions = Subscriptions()
    private let weakSource = WeakReference()
    private let valueClosure: () -> Model

    // For every copy of this ModelState that gets passed around (but not the original copy held by the Source), it needs to retain the underlying Source so that Source can continue to update it and apply business logic. If the Source is no longer retained by anything and all ModelStates are also release, the Source will deinit.
    fileprivate var source: AnyObject?
    private let passthrough = PassthroughSubject<Model, Never>()

    public var wrappedValue: Model {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value.value ?? valueClosure()
        }
        @available(*, unavailable)
        nonmutating set { }
    }

    public var model: Model { wrappedValue }
    public var projectedValue: ModelState<Model> {
        var new = self
        // Copy a strong reference to the original source over to all copies
        new.source = self.source ?? weakSource.object
        return new
    }

    // This implementation "hooks" into whenever a UIKit Renderer (UIViewController, UIView, etc.) that contains this property accesses the property — i.e. calls `self.model` — and automatically subscribes the Renderer to model updates if the Renderer isn't already subscribed. This makes UIKit Renderers work more like SwiftUI: no need to explicity subscribe to model updates. Just have the @ModelState property and updates will happen automatically
    public static subscript<T: AnyObject>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: KeyPath<T, Model>,
        storage storageKeyPath: KeyPath<T, ModelState<Model>>
    ) -> Model {
        get {
            let modelState = instance[keyPath: storageKeyPath]
            if let renderer = instance as? _Rendering & AnyObject {
                modelState.subscribe(subscriber: renderer, immediately: false) { [weak renderer] _ in
                    if Thread.isMainThread {
                        renderer?.render
                    } else {
                        DispatchQueue.main.async { renderer?.render }
                    }
                }
            }
            return modelState.wrappedValue
        }
        @available(*, unavailable)
        set { }
    }

    public init(wrappedValue: Model) {
        self.value = Observable(value: wrappedValue)
        self.valueClosure = { wrappedValue }
        self.lock = .init()
    }

    fileprivate init(modelClosure: @escaping () -> Model, source: AnyObject, lock: NSRecursiveLock) {
        self.value = .init(value: nil)
        self.valueClosure = modelClosure
        self.lock = lock
        weakSource.object = source
    }

    fileprivate func setModel(_ model: Model) {
        lock.lock()
        value.value = model
        lock.unlock()
        passthrough.send(model)
    }

    fileprivate func subscribe(immediately: Bool = true, _ closure: @escaping (Model) -> Void) -> AnyCancellable {
        defer { if immediately { closure(wrappedValue) } }
        return passthrough.sink {
            closure($0)
        }
    }

    fileprivate func subscribe(subscriber: AnyObject, immediately: Bool = true, closure: @escaping (Model) -> Void) {
        let subscriberKey = ObjectIdentifier(subscriber)
        lock.lock()
        if subscriptions[subscriberKey] == nil {
            subscriptions[subscriberKey] = .init { }
            subscriptions[subscriberKey] = subscribe(immediately: false) { [weak subscriber, weak lock, weak subscriptions] in
                guard subscriber != nil else {
                    lock?.lock()
                    subscriptions?[subscriberKey] = nil
                    lock?.unlock()
                    return
                }
                closure($0)
            }
            lock.unlock()
            if immediately {
                closure(wrappedValue)
            }
        } else {
            lock.unlock()
        }
    }

    fileprivate func unsubscribe(_ subscriber: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        subscriptions[ObjectIdentifier(subscriber)] = nil
    }
}

public extension ModelState {
    static var unsafePlaceholder: ModelState<Model> {
        .init(modelClosure: { fatalError("Attempting to access the value of an unsafe placeholder ModelState. You must replace the placeholder with a valid injected ModelState before attempting to access it") }, source: NoThreadsafeProperties(), lock: .init())
    }
}

extension ModelState: Identifiable where Model: Identifiable {
    public var id: Model.ID { model.id }
}

extension ModelState: Equatable where Model: Equatable {
    public static func ==(lhs: ModelState<Model>, rhs: ModelState<Model>) -> Bool {
        lhs.model == rhs.model
    }
}


// MARK: - ModelState Supporting Classes -

private class Subscriptions {
    private var dictionary = [ObjectIdentifier: AnyCancellable]()
    init() { }
    subscript(key: ObjectIdentifier) -> AnyCancellable? {
        get { dictionary[key] }
        set { dictionary[key] = newValue }
    }
}

private class WeakReference {
    weak var object: AnyObject?
    init() { }
}

private class Observable<Value>: ObservableObject {
    var objectWillChange: AnyPublisher<Void, Never>
    @Published var value: Value
    init(value: Value) {
        self.value = value
        self.objectWillChange = PassthroughSubject<Void, Never>().eraseToAnyPublisher()
        self.objectWillChange = $value.map{ _ in () }.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
}


// MARK: - Reflection Exempt Protocol and Extensions -

/// A protocol for specifying types that don't need to be reflected through when looking up existing Actions. For example, we don't need to reflect into a child Source, because it already manages its own Actions.
internal protocol ReflectionExempt { }

extension _Source: ReflectionExempt { }
extension Array: ReflectionExempt where Element: ReflectionExempt { }
extension Set: ReflectionExempt where Element: ReflectionExempt { }
extension Optional: ReflectionExempt where Wrapped: ReflectionExempt { }


// MARK: - Action Initializers -
fileprivate extension Action {
    init<T: CustomSourceProtocol>(identifier: String, source: T, method: @escaping (T) -> (Input) -> Void) {
        self.init(identifier: identifier) { [weak source] input in
            guard let source = source else {
                throw Action.Error.actionSourceDeinitialized(identifier)
            }
            guard source.hasCurrentAction(identifier: identifier) else {
                throw Action.Error.actionExpired(identifier)
            }
            method(source)(input)
        }
    }

    init<T: CustomSourceProtocol>(identifier: String, source: T, method: @escaping (T) -> () -> Void) where Input == Void {
        self.init(identifier: identifier) { [weak source] _ in
            guard let source = source else {
                throw Action.Error.actionSourceDeinitialized(identifier)
            }
            guard source.hasCurrentAction(identifier: identifier) else {
                throw Action.Error.actionExpired(identifier)
            }
            method(source)()
        }
    }
}

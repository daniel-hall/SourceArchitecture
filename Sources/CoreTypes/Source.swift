//
//  Source.swift
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
import Combine
import UIKit


// MARK: - Source -

open class Source<Model>: AnySource<Model>, SourceProtocol {
    public typealias SourceType = Source<Model>
    fileprivate var _modelClosure: (() -> Model)!
    fileprivate let _subscribeClosure: (AnyObject, @escaping () -> Void) -> Void
    
    public final override var model: Model {
        _modelClosure()
    }
    
    public init<T: SourceProtocol>(_ state: SourceState<T>) where T.Model == Model {
        self._subscribeClosure = state.subscribe
        super.init()
        state.source = self
        self._modelClosure = { [weak self] in
            state.isolatedState.lock.lock()
            defer {  state.isolatedState.lock.unlock() }
            return self?._model ?? state.isolatedState.initialModel()
        }
    }
    
    public init<T: SourceProtocol, MutableProperties>(_ mutableState: SourceMutableState<T, MutableProperties>) where T.Model == Model {
        self._subscribeClosure = mutableState.subscribe
        super.init()
        mutableState.source = self
        self._modelClosure = { [weak self] in
            mutableState.isolatedState.lock.lock()
            defer {  mutableState.isolatedState.lock.unlock() }
            return self?._model ?? mutableState.isolatedState.initialModel()
        }
    }
    
    public init(_ source: Source<Model>) {
        self._subscribeClosure = source._subscribeClosure
        super.init()
        self._modelClosure = { source.model }
        self._passthrough = source._passthrough
    }
    
    public init(_ source: () -> Source<Model>) {
        let source = source()
        self._subscribeClosure = source._subscribeClosure
        super.init()
        self._modelClosure = { source.model }
        self._passthrough = source._passthrough
    }
    
    public final func subscribe<T, U: Source<T>>(_ source: U, method: @escaping (U) -> () -> Void) {
        _subscribeClosure(source) { [weak source] in
            guard let source = source else { return }
            method(source)()
        }
    }
    
    internal final func subscribeTestClosure(_ closure: @escaping () -> Void) -> AnyCancellable {
        return _passthrough.sink { closure() }
    }
    
    public final override func subscribe<T: AnyObject & Renderer>(_ renderer: T) {
        _subscribeClosure(renderer) { [weak renderer] in
            if Thread.isMainThread {
                renderer?.render()
            } else {
                DispatchQueue.main.async {
                    renderer?.render()
                }
            }
        }
    }
}


// MARK: - AnySource -

/// The base class for all Sources, which does not include all the various extension methods and operators made available on Source subclasses. This allows it to be used by Renderers (views) without providing visibility or access to logical operations that should not be performed by a View
open class AnySource<Model>: AnySourceProtocol, ReflectionExempt {
    public typealias SourceType = AnySource<Model>
    fileprivate var _model: Model?
    fileprivate var _passthrough = PassthroughSubject<Void, Never>()
    public var model: Model { fatalError() }
    fileprivate init() {}
    public func subscribe<T: AnyObject & Renderer>(_ renderer: T) {
        fatalError()
    }
}

extension AnySource: ObservableObject {
    public var objectWillChange: AnyPublisher<Void, Never> {
        _passthrough.receive(on: DispatchQueue.main, options: nil).eraseToAnyPublisher()
    }
}

extension AnySource: Identifiable where Model: Identifiable {
    public var id: Model.ID { (self as! Source<Model>).model.id }
}

extension AnySource: Equatable where Model: Equatable {
    public static func ==(lhs: AnySource<Model>, rhs: AnySource<Model>) -> Bool {
        return lhs.model == rhs.model
    }
}


// MARK: - Source Protocols -

/// A protocol used for attaching specific static methods (like .fromValue or .unsafelyInitialized) _only_ to AnySource-typed instances (like in a Renderer) without making them visible or available to Sources or other subclasses (where they aren't relevant)
public protocol AnySourceProtocol: AnyObject {
    associatedtype SourceType: AnySourceProtocol
    associatedtype Model
    var model: Model { get }
}

/// A protocol used for attaching specific static methods (like .fromValue) _only_ to Source-typed instances without making them visible or available to custom Source subclasses (where they aren't relevant). Also used internally for other extension purposes
public protocol SourceProtocol: AnyObject {
    associatedtype SourceType: SourceProtocol
    associatedtype Model
    var model: Model { get }
}

public extension SourceProtocol {
    typealias State = SourceState<Self>
    typealias MutableState<MutableProperties> = SourceMutableState<Self, MutableProperties>
}

internal extension SourceProtocol {
    func hasCurrentAction(identifier: String) -> Bool {
        hasCurrentAction(identifier: identifier, in: model)
    }
    
    private func hasCurrentAction(identifier: String, in model: Any) -> Bool {
        if (model as? IdentifiableAction)?.identifier == identifier { return true }
        if model is ReflectionExempt { return false }
        return Mirror(reflecting: model).children.first { hasCurrentAction(identifier: identifier, in: $0.value) } != nil ? true : false
    }
}

/// A protocol for specifying types that don't need to be reflected through when looking up existing Actions. For example, we don't need to reflect into a child Source, because it already manages its own Actions.
internal protocol ReflectionExempt { }

extension Array: ReflectionExempt where Element: ReflectionExempt { }
extension Set: ReflectionExempt where Element: ReflectionExempt { }
extension Optional: ReflectionExempt where Wrapped: ReflectionExempt { }


// MARK: - State -

@dynamicMemberLookup
fileprivate class IsolatedState<Model, Properties> {
    private var properties: Properties
    fileprivate let lock = NSRecursiveLock()
    fileprivate let initialModel: () -> Model
    private var subscriptions = [ObjectIdentifier: AnyCancellable]()
    
    init(properties: Properties, initialModel: @escaping () -> Model) {
        self.properties = properties
        self.initialModel = initialModel
    }
    
    fileprivate func subscribe(source: Source<Model>, subscriber: AnyObject, method: @escaping () -> Void) {
        lock.lock()
        guard !subscriptions.keys.contains(ObjectIdentifier(subscriber)) else {
            lock.unlock()
            return
        }
        subscriptions[ObjectIdentifier(subscriber)] = source._passthrough.sink { method() }
        lock.unlock()
        method()
    }
    
    subscript<T>(dynamicMember keyPath: KeyPath<Properties, T>) -> T {
        lock.lock()
        defer { lock.unlock() }
        return properties[keyPath: keyPath]
    }
    
    subscript<T>(dynamicMember keyPath: WritableKeyPath<Properties, T>) -> T {
        get {
            lock.lock()
            defer { lock.unlock() }
            return properties[keyPath: keyPath]
        }
        set {
            lock.lock()
            properties[keyPath: keyPath] = newValue
            lock.unlock()
        }
    }
    
    func setModel(_ model: Model, source: Source<Model>) {
        lock.lock()
        source._model = model
        lock.unlock()
        source._passthrough.send()
    }
}

@dynamicMemberLookup
final public class SourceState<ParentSource: SourceProtocol> {
    fileprivate var isolatedState: IsolatedState<ParentSource.Model, Void>!
    fileprivate weak var source: Source<ParentSource.Model>?
    
    public init(model: @autoclosure @escaping () -> ParentSource.Model) {
        isolatedState = .init(properties: (), initialModel: model)
    }
    
    public init(model: @escaping (SourceState<ParentSource>) -> ParentSource.Model) {
        isolatedState = .init(properties: ()) { [unowned self] in
            return model(self)
        }
    }
    
    public func setModel(_ model: ParentSource.Model) {
        guard let source = source else { return }
        isolatedState.setModel(model, source: source)
    }
    
    fileprivate func subscribe(subscriber: AnyObject, method: @escaping () -> Void) {
        guard let source = source else { return }
        isolatedState.subscribe(source: source, subscriber: subscriber, method: method)
    }
}

@dynamicMemberLookup
public final class SourceMutableState<ParentSource: SourceProtocol, MutableProperties> {
    fileprivate var isolatedState: IsolatedState<ParentSource.Model, MutableProperties>!
    fileprivate weak var source: Source<ParentSource.Model>?
    
    public init(mutableProperties: MutableProperties, model: @autoclosure @escaping () -> ParentSource.Model) {
        isolatedState = .init(properties: mutableProperties, initialModel: model)
    }
    
    public init(mutableProperties: MutableProperties, model: @escaping (SourceMutableState<ParentSource, MutableProperties>) -> ParentSource.Model) {
        isolatedState = .init(properties: mutableProperties) { [unowned self] in
            return model(self)
        }
    }
    
    public subscript<T>(dynamicMember keyPath: KeyPath<MutableProperties, T>) -> T {
        isolatedState[dynamicMember: keyPath]
    }
    
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<MutableProperties, T>) -> T {
        get {
            isolatedState[dynamicMember: keyPath]
        }
        set {
            isolatedState[dynamicMember: keyPath] = newValue
        }
    }
    
    public func setModel(_ model: ParentSource.Model) {
        guard let source = source else { return }
        isolatedState.setModel(model, source: source)
    }
    
    fileprivate func subscribe(subscriber: AnyObject, method: @escaping () -> Void) {
        guard let source = source else { return }
        isolatedState.subscribe(source: source, subscriber: subscriber, method: method)
    }
}

public extension SourceState where ParentSource: ActionSource {
    subscript<T>(dynamicMember actionMethod: WritableKeyPath<ParentSource.Actions, ActionMethod<ParentSource, T>>) -> Action<T> {
        ParentSource.Actions().action(from: actionMethod, source: source as! ParentSource)
    }
}

public extension SourceMutableState where ParentSource: ActionSource {
    subscript<T>(dynamicMember actionMethod: WritableKeyPath<ParentSource.Actions, ActionMethod<ParentSource, T>>) -> Action<T> {
        ParentSource.Actions().action(from: actionMethod, source: source as! ParentSource)
    }
}


// MARK: - ActionSource -

public protocol ActionSource: SourceProtocol {
    associatedtype Actions: ActionMethods
}

public protocol ActionMethods {
    init()
}

fileprivate extension ActionMethods {
    func action<ParentSource: SourceProtocol, T>(from keyPath: WritableKeyPath<Self, ActionMethod<ParentSource, T>>, source: ParentSource) -> Action<T> {
        let method = self[keyPath: keyPath]
        let methodName = Mirror(reflecting: self).children.first { ($0.value as? ActionMethod<ParentSource, T>)?.uuid == method.uuid }!.label!
        let identifier = String(describing: ParentSource.self) + "." + methodName
        return .init(identifier: identifier, source: source, method: method.method)
    }
}

public struct ActionMethod<Source: SourceProtocol, Input> {
    fileprivate let uuid = UUID()
    fileprivate let method: (Source) -> (Input) -> Void
    public init(_ method: @escaping (Source) -> (Input) -> Void) {
        self.method = method
    }
    public init(_ method: @escaping (Source) -> () -> Void) where Input == Void {
        self.method = { source in { _ in method(source)() } }
    }
}

// MARK: - Action Initializers -
fileprivate extension Action {
    init<T: SourceProtocol>(identifier: String, source: T, method: @escaping (T) -> (Input) -> Void) {
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
    
    init<T: SourceProtocol>(identifier: String, source: T, method: @escaping (T) -> () -> Void) where Input == Void {
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

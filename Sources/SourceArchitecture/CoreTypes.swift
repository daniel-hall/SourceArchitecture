//
//  CoreTypes.swift
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


// MARK: - Source Type & Extensions -

/// A Source is a special kind of publisher that guarantees certain important properties:
///  - A Source always contains a current value of its Model (unlike Publishers in Combine)
///  - A Source has no external API for mutating its contents (unlike CurrentValueSubjec in Combine)
///  - A Source is a reference type (class) which means that it is never copied and all subscribers always get the exact same values, never a new series of values. This is important since a Source is a _single source of current truth_
///  - A Source automatically triggers an update on any Renderer (SwiftUI Views, UIKit ViewControllers and UIViews, etc.) when the Source's model value changes.
///  - A Source allows other Sources to subscribe to updated values without closures, to prevent accidental capture of values or needing to manage subscription tokens (AnyCancellables in Combine).
@propertyWrapper
public struct Source<Model>: DynamicProperty {
    public typealias Model = Model
    @ObservedObject private var source: ObservableSource<Model>

    public var model: Model { wrappedValue }
    public var wrappedValue: Model {
        get { source.model }
        @available(*, unavailable) nonmutating set {}
    }

    // This implementation "hooks" into whenever a UIKit Renderer (UIViewController, UIView, etc.) that contains this property accesses the property — i.e. calls `self.model` — and automatically subscribes the Renderer to model updates if the Renderer isn't already subscribed. This makes UIKit Renderers work more like SwiftUI: no need to explicity subscribe to model updates. Just have the @Soure property and updates will happen automatically
    public static subscript<T: AnyObject>(_enclosingInstance instance: T,
                                          wrapped wrappedKeyPath: KeyPath<T, Model>, storage storageKeyPath: KeyPath<T, Source<Model>>
    ) -> Model {
        get {
            /// If the type containing this Source is a Renderer (and a class type), then subscribe its `render()` method to updates if it isn't already subscribed
            if instance is any Renderer {
                instance[keyPath: storageKeyPath].source.subscribe(sendInitialModel: false, subscriber: instance) { [weak instance] _ in
                    if Thread.isMainThread {
                        (instance as? any Renderer)?.render()
                    } else {
                        DispatchQueue.main.async { (instance as? any Renderer)?.render() }
                    }
                }
            }
            return instance[keyPath: storageKeyPath].model
        }
        @available(*, unavailable) set {}
    }

    public init(model: Model) {
        source = ObservableSource(model)
    }

    fileprivate init<T: _SourceProtocol>(_ source: T) where T.Model == Model {
        self.source = ObservableSource(source)
    }

    /// A method for other Sources to subscribe to this Source's updates in order to assemble or apply logic to different streams of values. This style of subscription (passing in the subscriber and method) instead of a closure prevents accidental capturing of objects that can result in retain cycles and leaks. It also allows subscription without needing to manage an AnyCancellable token to keep the subscription alive.
    ///
    /// - Parameter sendInitialModel: pass in false if you *don't* want the subscriber method to be called with the initial model value and to instead only be called with future updates.
    @discardableResult
    public func subscribe<T: _SourceProtocol>(_ source: T, method: @escaping (T) -> (Model) -> Void, sendInitialModel: Bool = true) -> Source<Model> {
        self.source.subscribe(sendInitialModel: sendInitialModel, subscriber: source) { [weak source] in
            guard let source = source else { return }
            method(source)($0)
        }
        return self
    }

    /// A method for other Sources to subscribe to this Source's updates in order to assemble or apply logic to different streams of values. This style of subscription (passing in the subscriber and method) instead of a closure prevents accidental capturing of objects that can result in retain cycles and leaks. It also allows subscription without needing to manage an AnyCancellable token to keep the subscription alive.
    ///
    /// - Parameter sendInitialModel: pass in false if you *don't* want the subscriber method to be called with the initial model value and to instead only be called with future updates.
    @discardableResult
    public func subscribe<T: _SourceProtocol, U>(_ source: T, method: @escaping (T) -> (U) -> Void, sendInitialModel: Bool = true) -> Source<Model> where Model == U? {
        self.source.subscribe(sendInitialModel: sendInitialModel, subscriber: source) { [weak source] in
            guard let source = source, let model = $0 else { return }
            method(source)(model)
        }
        return self
    }

    /// A method for other Sources to subscribe to this Source's updates in order to assemble or apply logic to different streams of values. This style of subscription (passing in the subscriber and method) instead of a closure prevents accidental capturing of objects that can result in retain cycles and leaks. It also allows subscription without needing to manage an AnyCancellable token to keep the subscription alive.
    ///
    /// - Parameter sendInitialModel: pass in false if you *don't* want the subscriber method to be called with the initial model value and to instead only be called with future updates.
    @discardableResult
    public func subscribe<T: _SourceProtocol>(_ source: T, method: @escaping (T) -> () -> Void, sendInitialModel: Bool = true) -> Source<Model> {
        self.source.subscribe(sendInitialModel: sendInitialModel, subscriber: source) { [weak source] _ in
            guard let source = source else { return }
            method(source)()
        }
        return self
    }

    /// Unsubscribes a Source from receiving further updates when this Source's model changes
    public func unsubscribe<T: _SourceProtocol>(_ source: T) {
        self.source.unsubscribe(source)
    }

    /// A subscription method that accepts a closure to call when the model value changes. Only intended to be used for testing Sources in test target, so requires @testable import SourceArchitecture to be visible
    internal func subscribe(sendInitialModel: Bool = true, _ closure: @escaping (Model) -> Void) {
        self.source.subscribe(subscriber: source, closure: closure)
    }
}

/// Combine interoperability
public extension Source {
    func eraseToAnyPublisher() -> AnyPublisher<Model, Never> {
        defer { source.publisher.send(source.model) }
        return source.publisher.eraseToAnyPublisher()
    }
}

public extension _Source {
    /// A property wrapper that can only be used by Sources in order to create an Action which will call a method on the Source when invoked. The method which should be called is declared along with the property, e.g. `@ActionFromMethod(doSomething) var doSomethingAction`
    @propertyWrapper
    struct ActionFromMethod<Source: _SourceProtocol, Input> {
        /// This property is unvailable and never callable, since the wrappedValue will instead be accessed through the static subscript in order to get a reference to the containing Source
        @available(*, unavailable)
        public var wrappedValue: SourceArchitecture.Action<Input> { fatalError() }
        private let uuid = UUID().uuidString
        private let method: (Source) -> (Input) -> Void

        /// This method of returning the wrappedValue allows us to also access the Source instance that contains this property. It also allows us to restrict usage of the @ActionFromMethod property wrapper to only be used in Source
        public static subscript(
            _enclosingInstance instance: Source,
            wrapped wrappedKeyPath: KeyPath<Source, SourceArchitecture.Action<Input>>,
            storage storageKeyPath: KeyPath<Source, ActionFromMethod<Source, Input>>
        ) -> SourceArchitecture.Action<Input> {
            let action = instance[keyPath: storageKeyPath]
            // Reflect through all properties of our containing instance until we find the one that is this instance, and get the label. That will tell us what this Action is named based on its property name.
            let identifier = Mirror(reflecting: instance).children.first { ($0.value as? Self)?.uuid  == action.uuid }!.label!.dropFirst()
            return .init(actionIdentifier: String(identifier), source: instance, method: action.method)
        }

        /// Initialize this property wrapper by passing in the method that you want to be called by this Action. For example: `@ActionFromMethod(doSomething) var doSomethingAction`
        public init(_ method: @escaping (Source) -> (Input) -> Void) {
            self.method = method
        }

        /// Initialize this property wrapper by passing in the method that you want to be called by this Action. For example: `@ActionFromMethod(doSomething) var doSomethingAction`
        public init(_ method: @escaping (Source) -> () -> Void) where Input == Void {
            self.method = { source in { [weak source] _ in if let source = source { return method(source)() } } }
        }
    }

    /// A property wrapper that makes a property on a Source thread safe by using the Source's lock when reading and writing the value.
    @propertyWrapper
    class Threadsafe<Value> {
        public var wrappedValue: Value {
            @available(*, unavailable) get { fatalError() }
            @available(*, unavailable) set { fatalError() }
        }
        private var value: Value

        /// This method of returning the wrappedValue allows us to also access the Source instance that contains this property in order to use its lock. It also allows us to restrict usage of the @Threadsafe property wrapper to only be used within Sources
        public static subscript<T: _SourceProtocol>(
            _enclosingInstance instance: T,
            wrapped wrappedKeyPath: KeyPath<T, Value>,
            storage storageKeyPath: KeyPath<T, Threadsafe<Value>>
        ) -> Value {
            get {
                let threadsafe = instance[keyPath: storageKeyPath]
                instance.lock.lock()
                defer { instance.lock.unlock() }
                return threadsafe.value
            }
            set {
                let threadsafe = instance[keyPath: storageKeyPath]
                instance.lock.lock()
                threadsafe.value = newValue
                instance.lock.unlock()
            }
        }

        public init(wrappedValue: Value) {
            self.value = wrappedValue
        }
    }
}

public extension Source {
    func optional() -> Source<Model?> {
        map { Optional($0) }
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

extension Source: Hashable where Model: Hashable {
    public func hash(into hasher: inout Hasher) {
        model.hash(into: &hasher)
    }
}

// MARK: - Source Protocols and Base Types

/// A typealias used to create new Sources, which must both subclass `_Source<Model>` and conform to `_SourceProtocol`. This typealias allows new Sources to do both with a single supertype, e.g. `class MySource: SourceOf<String>`
public typealias SourceOf<Model> = _Source<Model> & _SourceProtocol

public protocol _SourceProtocol: _RestrictedSource, _AssociatedModelProtocol {
    var initialModel: Model { get }
}

public extension _SourceProtocol {
    /// The current model value for this Source. This default implementation of the `model` property uses locking for thread safety and automatically publishes new values to subscribers.
    var model: Model {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let model = _model as? Model {
                return model
            }
            let model = initialModel
            (self as? any (_SourceProtocol & DecodableActionSource))?.setSourceOn(model: model)
            return model
        }
        set {
            lock.lock()
            let model = newValue
            (self as? any (_SourceProtocol & DecodableActionSource))?.setSourceOn(model: model)
            _model = model
            lock.unlock()
        }
    }

    /// Create a type-erased Source of the Model type from this implementation, which can be used by Renderers or subscribed to by other Sources.
    func eraseToSource<T>() -> Source<T> where Model == T {
        Source(self)
    }
}

fileprivate extension _SourceProtocol {
    var lock: NSRecursiveLock {
        (self as! _Source<Model>).lock
    }

    var publisher: PassthroughSubject<Model, Never> {
        (self as! _Source<Model>).publisher
    }

    var _model: Any {
        get { (self as! _Source<Model>)._model }
        set { (self as! _Source<Model>)._model = newValue }
    }

    func hasCurrentAction(identifier: String) -> Bool {
        hasCurrentAction(identifier: identifier, in: model)
    }

    func hasCurrentAction(identifier: String, in model: Any) -> Bool {
        if (model as? IdentifiableAction)?.actionIdentifier == identifier { return true }
        if model is ReflectionExempt { return false }
        return Mirror(reflecting: model).children.first { hasCurrentAction(identifier: identifier, in: $0.value) } != nil ? true : false
    }
}

public protocol _AssociatedModelProtocol {
    associatedtype Model
}

/// A ComposedSource doesn't implement its own state or business logic, it merely assembles and / or transforms other Sources. Subclass it with all the parameters needed in the initializer, then call super.init with a closure that returns the assembled Source.
open class ComposedSource<Model> {
    private lazy var source = sourceClosure()
    private let sourceClosure: () -> Source<Model>
    public init(_ source: @escaping () -> Source<Model>) {
        sourceClosure = source
    }
    public func eraseToSource() -> Source<Model> {
        source
    }
}

/// The ultimate base class for Sources. It can only be subclassed / initialized within the SourceArchitecture framework
open class _RestrictedSource {
    fileprivate init() { }
}

/// The superclass for all Sources. Contains the lock used for updating the model, changing threadsafe properties, and subscribing.
open class _Source<Model>: _RestrictedSource, _AssociatedModelProtocol {
    public typealias Model = Model
    fileprivate let lock = NSRecursiveLock()
    fileprivate let publisher = PassthroughSubject<Model, Never>()
    fileprivate var _model: Any = Empty() {
        didSet {
            if let model = _model as? Model {
                publisher.send(model)
            }
        }
    }
    public override init() { }
}


// MARK: - Action -

/// An Action provides a way to invoke a method on Source without the caller needing to know about the Source or the method. Actions can accept an input parameter and are used to trigger behaviors in response to user interaction or other application events.
public struct Action<Input>: Codable {
    public enum CodingKeys: String, CodingKey {
        case actionIdentifier
        case sourceIdentifier
    }
    public static func placeholder(file: String = #file, line: Int = #line, column: Int = #column) -> Action<Input> {
        let sourceIdentifier = file + ":\(line),\(column)"
        return .init(actionIdentifier: "placeholder", sourceIdentifier: sourceIdentifier) {
            assertionFailure("Attempted to execute a placeholder Action created at \(sourceIdentifier)")
            ActionExecution._publisher.send(.init(sourceIdentifier: sourceIdentifier, actionIdentifier: "placeholder", input: $0, error: Error.placeholderActionInvoked(sourceIdentifier)))
        }
    }
    internal let actionIdentifier: String
    private let sourceIdentifier: String
    private let source: WeakReference
    private let execute: (Input) throws -> Void

    public var description: String {
        sourceIdentifier + "." + actionIdentifier
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let actionIdentifier = try values.decode(String.self, forKey: .actionIdentifier)
        let sourceIdentifier = try values.decode(String.self, forKey: .sourceIdentifier)
        let source = WeakReference()
        self.actionIdentifier = actionIdentifier
        self.sourceIdentifier = sourceIdentifier
        self.source = source
        self.execute = { [weak source] input in
            guard let source = source?.object as? (any (_SourceProtocol & DecodableActionSource)), source.decodableActionSourceIdentifier == sourceIdentifier else {
                throw Error.actionDecodedByWrongSource(sourceIdentifier + "." + actionIdentifier)
            }
            guard source.hasCurrentAction(identifier: actionIdentifier) else {
                throw Action.Error.actionExpired(actionIdentifier)
            }
            guard let method = (Mirror(reflecting: source).children.first(where: { String($0.label?.dropFirst() ?? "") == actionIdentifier })?.value as? SourceMethodResolving)?.resolvedMethod(for: source, input: input) else {
                throw Error.actionDecodedWithInvalidMethod(sourceIdentifier + "." + actionIdentifier)
            }
            method()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionIdentifier, forKey: .actionIdentifier)
        try container.encode(sourceIdentifier, forKey: .sourceIdentifier)
    }

    /// Initialize with an arbitrary closure for testing
    internal init(actionIdentifier: String = "Closure", sourceIdentifier: String = "Test", testClosure: @escaping (Input) throws -> Void) {
        self.actionIdentifier = actionIdentifier
        self.sourceIdentifier = sourceIdentifier
        self.source = WeakReference()
        self.execute = { try testClosure($0) }
    }

    /// Creates an Action which accepts a different type of input, but calls through to this original action. When the new Action is invoked with the new input, it will transform that input to the original input type and use that invoke the original Action.
    public func map<NewInput>(actionIdentifier: String = "\(#file).\(#line) MappedAction" , transform: @escaping (NewInput) -> Input) -> Action<NewInput> {
        .init(actionIdentifier: actionIdentifier, sourceIdentifier: self.description) {
            try self.execute(transform($0))
        }
    }
}


// MARK: - Action Extensions -

public extension Action {
    // Executes the Action with the provided input. If a closure is provided as well, then the closure will be called if the Action is unavailable because the underlying Source has deinitialized or is in a different state that doesn't allow this Action. Return true from the closure to propogate the error to the ActionExecution.errors stream as well, or false to not include it in the stream for further handling.
    func callAsFunction(_ input: Input, ifUnavailable: ((ActionExecution) -> Bool)? = nil) {
        do {
            try execute(input)
            ActionExecution._publisher.send(.init(sourceIdentifier: sourceIdentifier, actionIdentifier: actionIdentifier, input: input, error: nil))
        } catch {
            _ = ActionExecution._errors
            let execution = ActionExecution(sourceIdentifier: sourceIdentifier, actionIdentifier: actionIdentifier, input: input, error: error)
            if let ifUnavailable = ifUnavailable {
                if ifUnavailable(execution) {
                    ActionExecution._publisher.send(execution)
                }
            } else {
                ActionExecution._publisher.send(execution)
            }
        }
    }
}

public extension Action where Input == Void {
    // Executes the Action. If a closure is provided as well, then the closure will be called if the Action is unavailable because the underlying Source has deinitialized or is in a different state that doesn't allow this Action. Return true from the closure to propogate the error to the ActionExecution.errors stream as well, or false to not include it in the stream for further handling.
    func callAsFunction(ifUnavailable: ((ActionExecution) -> Bool)? = nil) {
        callAsFunction((), ifUnavailable: ifUnavailable)
    }
}

extension Action: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(description)
    }
}

extension Action: Equatable {
    public static func == (lhs: Action<Input>, rhs: Action<Input>) -> Bool {
        return lhs.actionIdentifier == rhs.actionIdentifier
    }
}

fileprivate extension Action {
    enum Error: LocalizedError {
        typealias ActionDescription = String
        case actionSourceDeinitialized(ActionDescription)
        case actionExpired(ActionDescription)
        case actionDecodedByWrongSource(ActionDescription)
        case actionDecodedWithInvalidMethod(ActionDescription)
        case placeholderActionInvoked(ActionDescription)

        public var errorDescription: String? {
            switch self {
            case .actionSourceDeinitialized(let action): return "Attempted to execute an Action from a Source that was deinitialized and can therefore no longer execute the underlying method. The Action's description is: \(action)."
            case .actionExpired(let action): return "Attempted to execute an expired Action with description: \(action). Expired Actions are those which were part of a Source's previous model state, but not its current model state."
            case .actionDecodedByWrongSource(let action): return "Attempted to execute an Action that was decoded by a different Source than it was encoded with. The Action's description is: \(action)."
            case .actionDecodedWithInvalidMethod(let action): return "Attempted to execute an Action that was decoded with an identifier that does not map to a method on the Source or maps to a method with the wrong input type. The Action's description is: \(action)."
            case .placeholderActionInvoked(let action): return "Attempted to execute a placeholder Action create at \(action)"
            }
        }
    }

    init<T: _SourceProtocol>(actionIdentifier: String, source: T, method: @escaping (T) -> (Input) -> Void) {
        let sourceIdentifier = (source as? DecodableActionSource)?.decodableActionSourceIdentifier ?? String(describing: type(of: source))
        self.init(actionIdentifier: actionIdentifier, sourceIdentifier: sourceIdentifier) { [weak source] input in
            guard let source = source else {
                throw Action.Error.actionSourceDeinitialized(actionIdentifier)
            }
            guard source.hasCurrentAction(identifier: actionIdentifier) else {
                throw Action.Error.actionExpired(actionIdentifier)
            }
            method(source)(input)
        }
    }

    init<T: _SourceProtocol>(actionIdentifier: String, source: T, method: @escaping (T) -> () -> Void) where Input == Void {
        let sourceIdentifier = (source as? DecodableActionSource)?.decodableActionSourceIdentifier ?? String(describing: type(of: source))
        self.init(actionIdentifier: actionIdentifier, sourceIdentifier: sourceIdentifier) { [weak source] _ in
            guard let source = source else {
                throw Action.Error.actionSourceDeinitialized(actionIdentifier)
            }
            guard source.hasCurrentAction(identifier: actionIdentifier) else {
                throw Action.Error.actionExpired(actionIdentifier)
            }
            method(source)()
        }
    }
}

fileprivate protocol IdentifiableAction {
    var actionIdentifier: String { get }
    func setSourceIfNeeded(_ source: any _SourceProtocol)
}

extension Action: IdentifiableAction {
    fileprivate func setSourceIfNeeded(_ source: any _SourceProtocol) {
        guard source is DecodableActionSource else { return }
        guard self.source.object == nil else { return }
        guard (source as? DecodableActionSource)?.decodableActionSourceIdentifier == sourceIdentifier else { return }
        self.source.object = source
    }
}

/// A record of an Action being executed, including the description and input that was used
public struct ActionExecution {

    public static let publisher = _publisher.eraseToAnyPublisher()
    fileprivate static let _publisher = PassthroughSubject<ActionExecution, Never>()

    public static var errors: AnyPublisher<ActionExecution, Never> {
        defer {
            _defaultErrorSubscription?.cancel()
            _defaultErrorSubscription = nil
        }
        return _errors.eraseToAnyPublisher()
    }
    fileprivate static let _errors = {
        let publisher = ActionExecution.publisher.filter { $0.error != nil }
        _defaultErrorSubscription = publisher.sink { execution in
            guard let error = execution.error else { return }
            // assert ensures it only runs in non-release builds
            assert({
                print(error)
                return true
            }())
        }
        return publisher
    }()

    private static var _defaultErrorSubscription: AnyCancellable?

    public let sourceIdentifier: String
    public let actionIdentifier: String
    public var description: String { sourceIdentifier + "." + actionIdentifier }
    public let input: Any
    public let error: Error?
}


// MARK: - DecodableActionSource Protocols

/// A protocol that is conformed to by Sources which intend to decode models with Actions. Conforming to this protocol is required for hooking up decoded Actions to the correct method on a Source
public protocol DecodableActionSource {
    var decodableActionSourceIdentifier: String { get }
}

public extension DecodableActionSource {
    var decodableActionSourceIdentifier: String { String(describing: type(of: self)) }
}

fileprivate extension _SourceProtocol where Self: DecodableActionSource {
    func setSourceOn(model: Any) {
        if let action = model as? IdentifiableAction {
            action.setSourceIfNeeded(self)
            return
        }
        if model is ReflectionExempt { return }
        return Mirror(reflecting: model).children.forEach { setSourceOn(model: $0.value) }
    }
}

/// A private protocol used for connecting decoded Actions to the correct method on a Source
fileprivate protocol SourceMethodResolving {
    func resolvedMethod<ResolvedInput, ForSource: _SourceProtocol>(for source: ForSource, input: ResolvedInput) -> (() -> Void)?
}

extension _Source.ActionFromMethod: SourceMethodResolving {
    /// Retrieves the method that should be called by a decoded Action
    fileprivate func resolvedMethod<ResolvedInput, ForSource: _SourceProtocol>(for source: ForSource, input: ResolvedInput) -> (() -> Void)? {
        guard let source = source as? Source, let input = input as? Input else { return nil }
        return { method(source)(input) }
    }
}


// MARK: - Private Helper Types -

/// A private implementation type which implements ObservableObject to trigger updates from the containing @Source property wrapper in SwiftUI Views. It also holds a dictionary of subscriptions and provides a way to subscribe to the underlying  Source's value.
private final class ObservableSource<Model>: ObservableObject {
    let objectWillChange: AnyPublisher<Void, Never>
    var model: Model { modelClosure() }
    let lock: NSRecursiveLock
    let publisher: PassthroughSubject<Model, Never>
    let modelClosure: () -> Model
    var subscriptions = [ObjectIdentifier: AnyCancellable]()

    init<T: _SourceProtocol>(_ source: T) where T.Model == Model {
        lock = source.lock
        publisher = source.publisher
        modelClosure = { source.model }
        objectWillChange = source.publisher.map { _ in () }.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    init(_ model: Model) {
        lock = .init()
        let publisher = PassthroughSubject<Model, Never>()
        self.publisher = publisher
        modelClosure = { model }
        objectWillChange = publisher.map { _ in () }.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    func unsubscribe<T: AnyObject>(_ subscriber: T) {
        lock.lock()
        subscriptions[ObjectIdentifier(subscriber)] = nil
        lock.unlock()
    }

    func subscribe<T: AnyObject>(sendInitialModel: Bool = true, subscriber: T, closure: @escaping (Model) -> Void) {
        let identifier = ObjectIdentifier(subscriber)
        lock.lock()
        if subscriptions[identifier] == nil {
            subscriptions[identifier] = publisher.sink { [weak subscriber, weak self] in
                guard subscriber != nil else {
                    self?.lock.lock()
                    self?.subscriptions[identifier] = nil
                    self?.lock.unlock()
                    return
                }
                closure($0)
            }
            lock.unlock()
            if sendInitialModel {
                closure(model)
            }
        } else {
            lock.unlock()
        }
    }
}

private class WeakReference {
    weak var object: AnyObject?
    init() { }
}

private struct Empty { }


// MARK: - Reflection Exempt Protocol and Extensions -

/// A protocol for specifying types that shouldn't be reflected through when looking up existing Actions. For example, we don't need to reflect into a child Source, because it already manages its own Actions. Not skipping these types can cause excessive or infinite recursion
fileprivate protocol ReflectionExempt { }

extension Source: ReflectionExempt { }
extension _Source: ReflectionExempt { }
extension Array: ReflectionExempt where Element: ReflectionExempt { }
extension Set: ReflectionExempt where Element: ReflectionExempt { }
extension Optional: ReflectionExempt where Wrapped: ReflectionExempt { }


// MARK: - Renderer Protocol -

public protocol Renderer {
    associatedtype Model
    var model: Model { get nonmutating set }
    func render()
}

public extension Renderer where Self: View {
    func render() { }
}

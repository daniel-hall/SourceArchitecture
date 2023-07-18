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
import Combine
import SwiftUI


// MARK: - Source Types and Protocols -

/// A Source is a special kind of publisher that guarantees certain important properties:
///  - A Source always contains a current state of its Model (unlike Publishers in Combine)
///  - A Source has no external API for mutating its contents (unlike CurrentValueSubject in Combine)
///  - A Source is a reference type (class) which means that it is never copied and all subscribers always get the exact same values, never a new series of values. This is important since a Source is a _single source of current truth_
///  - A Source automatically triggers an update on any Renderer (SwiftUI Views, UIKit ViewControllers and UIViews, etc.) when the Source's model value changes.
///  - A Source is connected directly to a method using the @Sourced property wrapper. No closures are involved in subscriptions, which prevents accidental retain cycles
///
/// This typealias is used to create new Sources, which must both subclass `_Source<Model>` and conform to `_SourceProtocol`. This typealias allows new Sources to do both with a single supertype, e.g. `class MySource: Source<String>`
public typealias Source<Model> = SourceArchitecture.Source<Model> & SourceProtocol

public protocol SourceProtocol: AnyObject {
    associatedtype Model
    typealias Sourced<T> = SourceArchitecture.Sourced<Self, T>
    var initialState: Model { get }
    /// An optional method that can be implemented to run some behavior the first time this Source's state is accessed
    func onStart()
}

public extension SourceProtocol {
    func onStart() {
        // No-op by default
    }

    /// The current model value for this Source. This default implementation of the `model` property uses locking for thread safety and automatically publishes new values to subscribers.
    var state: Model {
        get {
            guard let source = (self as? SourceArchitecture.Source<Model>) else {
                return initialState
            }
            // If our state has already been initialized previously, return it immediately
            if let state = source.observable.state {
                return state
            }
            // Otherwise, create initial state and run first-time access behaviors
            let state = initialState
            (self as? any (SourceProtocol & DecodableActionSource))?.setSourceOn(state: state)
            source.observable.state = state
            // Set this Source as the parent of any @Sourced properties
            Mirror(reflecting: self).children.forEach {
                if $0.label?.hasPrefix("_") == true {
                    ($0.value as? any Parentable)?.setParent(self)
                }
            }
            self.onStart()
            return state
        }
        set {
            let state = newValue
            (self as? any (SourceProtocol & DecodableActionSource))?.setSourceOn(state: state)
            (self as? SourceArchitecture.Source<Model>)?.observable.state = state
        }
    }

    /// Create a type-erased Source of the Model type from this implementation, which can be used by Renderers or subscribed to by other Sources.
    func eraseToAnySource<T>() -> AnySource<T> where Model == T, Self: Source<Model> {
        AnySource(self)
    }
}

fileprivate extension SourceProtocol {

    func hasCurrentAction(identifier: String) -> Bool {
        hasCurrentAction(identifier: identifier, in: state)
    }

    private func hasCurrentAction(identifier: String, in state: Any) -> Bool {
        if (state as? IdentifiableAction)?.actionIdentifier == identifier { return true }
        if state is ReflectionExempt { return false }
        return Mirror(reflecting: state).children.first { hasCurrentAction(identifier: identifier, in: $0.value) } != nil ? true : false
    }
}

public enum SourceArchitecture {
    /// The superclass for all Sources. Contains the observable state and publishers used for subscriptions, etc.
    open class Source<Model> {
        public typealias Model = Model
        fileprivate let lock = NSRecursiveLock()
        fileprivate let observable = Observed<Model>()
        public init() { }
    }

    /// A property wrapper that connects and updates a property's value from the state of an underlying Source.
    /// The wrapper also calls the provided method every time the underlying Source updates.
    /// For parent types that conform to the Renderer protocol, the method to call on Source updates can't be
    /// specified as it will always be the Renderer's `render()` method.
    @propertyWrapper
    public struct Sourced<Parent, Model>: DynamicProperty, Parentable {

        private final class Storage<StorageParent, StorageModel>: ObservableObject {
            let objectWillChange = PassthroughSubject<Any, Never>()
            let sourceClosure: ((StorageParent) -> AnySource<StorageModel>)?
            var subscription: AnyCancellable?
            var method: (StorageParent) -> (StorageModel) -> Void
            var isRendering = false
            let lock = NSRecursiveLock()
            private weak var weakParent: AnyObject?
            var parent: StorageParent? {
                get { weakParent as? StorageParent }
                set { weakParent = newValue as? AnyObject }
            }

            /// method to republish the new underlying Source's objectWillChange updates to our own publisher
            ///  to trigger SwiftUI updates
            func observe(_ source: AnySource<StorageModel>) {
                lock.lock()
                subscription = source.objectWillChange.sink {  [weak self] value in
                    if let self {
                        self.objectWillChange.send(value as Any)
                    }
                }
                lock.unlock()
                objectWillChange.send(source.state)
            }

            lazy var source: AnySource<StorageModel> = sourceClosure!(self.parent!)
            {
                didSet {
                    observe(source)
                    lock.lock()
                    if let parent = parent {
                        subscription = source.objectDidChange.sink { [weak self] state in
                            if let self, let parent = self.weakParent as? StorageParent {
                                self.method(parent)(state)
                            }
                        }
                        lock.unlock()
                        self.method(parent)(source.state)
                    }
                    else {
                        lock.unlock()
                    }
                }
            }
            init(method: ((StorageParent) -> (StorageModel) -> Void)?, sourceClosure: ((StorageParent) -> AnySource<StorageModel>)? = nil) {
                self.method = { _ in { _ in } }
                self.sourceClosure = sourceClosure
                self.method = method ?? { [weak self] parent in
                    { [weak self] _ in
                        guard let self else { return }
                        if !Thread.isMainThread {
                            DispatchQueue.main.async {
                                (parent as? any Renderer)?.render()
                            }
                        } else {
                            if self.isRendering { return }
                            self.isRendering = true
                            (parent as? any Renderer)?.render()
                            self.isRendering = false
                        }
                    }
                }
            }

            func setParent(_ parent: AnyObject) {
                guard self.parent == nil, let parent = parent as? StorageParent else {
                    return
                }
                self.parent = parent
                lock.lock()
                subscription = source.objectDidChange.sink { [weak self] state in
                    if let self, let parent = self.weakParent as? StorageParent {
                        self.method(parent)(state)
                    }
                }
                lock.unlock()
            }
        }

        @ObservedObject private var storage: Storage<Parent, Model>

        public var wrappedValue: Model {
            storage.source.state
        }

        fileprivate func setParent(_ parent: AnyObject) {
            storage.setParent(parent)
        }

        public static subscript(
            _enclosingInstance instance: Parent,
            wrapped wrappedKeyPath: KeyPath<Parent, Model>,
            storage storageKeyPath: ReferenceWritableKeyPath<Parent,  Sourced<Parent, Model>>
        ) -> Model {
            let sourced = instance[keyPath: storageKeyPath]
            sourced.setParent(instance as AnyObject)
            return sourced.wrappedValue
        }

        public func clearSource<T>() where Model == T? {
            setSource(SingleValueSource<Model>(nil).eraseToAnySource())
        }

        public func setSource<T>(_ source: AnySource<T>) where Model == T? {
            storage.source = source.map { Model.some($0) }
        }

        public func setSource(_ source: AnySource<Model>) {
            storage.source = source
        }

        public init(from source: AnySource<Model>, updating method: @escaping (Parent) -> (Model) -> Void) where Parent: SourceProtocol {
            storage = .init(method: method)
            storage.source = source
        }

        public init(from source: AnySource<Model>, updating method: @escaping (Parent) -> () -> Void) where Parent: SourceProtocol {
            storage = .init(method: { parent in { _ in method(parent)() } })
            storage.source = source
        }

        public init(from keyPath: KeyPath<Parent, AnySource<Model>>, updating method: @escaping (Parent) -> (Model) -> Void) where Parent: SourceProtocol {
            storage = .init(method: method, sourceClosure: { $0[keyPath: keyPath] })
        }

        public init(from keyPath: KeyPath<Parent, AnySource<Model>>, updating method: @escaping (Parent) -> () -> Void) where Parent: SourceProtocol {
            storage = .init(method: { parent in { _ in method(parent)() } }, sourceClosure: { $0[keyPath: keyPath] })
        }

        public init<T>(updating method: @escaping (Parent) -> (Model) -> Void) where Parent: SourceProtocol, Model == T? {
            storage = .init(method: method)
            storage.source = SingleValueSource<Model>(nil).eraseToAnySource()
        }

        public init<T>(updating method: @escaping (Parent) -> (T) -> Void) where Parent: SourceProtocol, Model == T? {
            storage = .init(method: { parent in { if let state = $0 { method(parent)(state) } } })
            storage.source = SingleValueSource<Model>(nil).eraseToAnySource()
        }

        public init<T>(updating method: @escaping (Parent) -> () -> Void) where Parent: SourceProtocol, Model == T? {
            storage = .init(method: { parent in { _ in method(parent)() } })
            storage.source = SingleValueSource<Model>(nil).eraseToAnySource()
        }

        public init(from source: AnySource<Model>) where Parent: Renderer {
            storage = .init(method: nil)
            storage.source = source
            storage.observe(source)
        }

        public init(from keyPath: KeyPath<Parent, AnySource<Model>>) where Parent: Renderer {
            storage = .init(method: nil, sourceClosure: { $0[keyPath: keyPath] })
        }

        public init<T>() where Parent: Renderer, Model == T? {
            storage = .init(method: nil)
            storage.source = SingleValueSource<Model>(nil).eraseToAnySource()
        }
    }
}

public extension SourceArchitecture.Source {
    /// A property wrapper that makes a property on a Source thread safe by using the Source's lock when reading and writing the value.
    @propertyWrapper
    final class Threadsafe<Value> {
        public var wrappedValue: Value {
            @available(*, unavailable) get { fatalError() }
            @available(*, unavailable) set { fatalError() }
        }
        private var value: Value

        /// This method of returning the wrappedValue allows us to also access the Source instance that contains this property in order to use its lock. It also allows us to restrict usage of the @Threadsafe property wrapper to only be used within Sources
        public static subscript<Model, T: Source<Model>>(
            _enclosingInstance instance: T,
            wrapped wrappedKeyPath: KeyPath<T, Value>,
            storage storageKeyPath: KeyPath<T, Threadsafe<Value>>
        ) -> Value {
            get {
                instance.lock.lock()
                let threadsafe = instance[keyPath: storageKeyPath]
                defer { instance.lock.unlock() }
                return threadsafe.value
            }
            set {
                instance.lock.lock()
                let threadsafe = instance[keyPath: storageKeyPath]
                threadsafe.value = newValue
                instance.lock.unlock()
            }
        }

        public init(wrappedValue: Value) {
            self.value = wrappedValue
        }
    }

    /// A property wrapper that can only be used by Sources in order to create an Action which will call a method on the Source when invoked. The method which should be called is declared along with the property, e.g. `@ActionFromMethod(doSomething) var doSomethingAction`
    @propertyWrapper
    struct ActionFromMethod<Source: SourceProtocol, Input> {
        /// This property is unvailable and never callable, since the wrappedValue will instead be accessed through the static subscript in order to get a reference to the containing Source
        @available(*, unavailable)
        public var wrappedValue: Action<Input> { fatalError() }
        private let uuid = UUID().uuidString
        private let method: (Source) -> (Input) -> Void

        /// This method of returning the wrappedValue allows us to also access the Source instance that contains this property. It also allows us to restrict usage of the @ActionFromMethod property wrapper to only be used in Source
        public static subscript(
            _enclosingInstance instance: Source,
            wrapped wrappedKeyPath: KeyPath<Source, Action<Input>>,
            storage storageKeyPath: KeyPath<Source, ActionFromMethod<Source, Input>>
        ) -> Action<Input> {
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
}


// MARK: - AnySource Type & Extensions -

public struct AnySource<Model> {
    fileprivate let objectWillChange: Publishers.ReceiveOn<Published<Model?>.Publisher, RunLoop>
    fileprivate let objectDidChange: PassthroughSubject<Model, Never>
    fileprivate let stateClosure: () -> Model
    public var state: Model { stateClosure() }

    fileprivate init<T: Source<Model>>(_ source: T) where T.Model == Model {
        stateClosure = { source.state }
        objectWillChange = source.observable.objectWillChange
        objectDidChange = source.observable.objectDidChange
    }
}

/// Combine interoperability
public extension AnySource {
    func eraseToAnyPublisher() -> AnyPublisher<Model, Never> {
        defer { objectDidChange.send(state) }
        return objectDidChange.eraseToAnyPublisher()
    }
}

extension AnySource: CustomDebugStringConvertible {
    public var debugDescription: String { "AnySource<\(Model.self)>(state: \(state))" }
}

extension AnySource: CustomStringConvertible {
    public var description: String { "AnySource<\(Model.self)>(state: \(state))" }
}

extension AnySource: Identifiable where Model: Identifiable {
    public var id: Model.ID { state.id }
}

extension AnySource: Equatable where Model: Equatable {
    public static func ==(lhs: AnySource<Model>, rhs: AnySource<Model>) -> Bool {
        lhs.state == rhs.state
    }
}

extension AnySource: Hashable where Model: Hashable {
    public func hash(into hasher: inout Hasher) {
        state.hash(into: &hasher)
    }
}

// MARK: - Renderer Protocol & Extensions -

public protocol Renderer {
    associatedtype Model
    var model: Model { get }
    func render()
}

public extension Renderer {
    typealias Sourced<Model> = SourceArchitecture.Sourced<Self, Model>
}

public extension Renderer where Self: View {
    func render() { }
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
            ActionExecution.subject.send(.init(sourceIdentifier: sourceIdentifier, actionIdentifier: "placeholder", input: $0, error: Error.placeholderActionInvoked(sourceIdentifier)))
        }
    }
    internal let actionIdentifier: String
    private let sourceIdentifier: String
    private let source: WeakReference
    private let execute: (Input) throws -> Void

    public var description: String {
        "Action<\(Input.self)>"
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
            guard let source = source?.object as? (any (SourceProtocol & DecodableActionSource)), source.decodableActionSourceIdentifier == sourceIdentifier else {
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
    /// Executes the Action with the provided input. If a closure is provided as well, then the closure will be called if the Action is unavailable because the underlying Source has deinitialized or is in a different state that doesn't allow this Action. Return true from the closure to propogate the error to the ActionExecution.errors stream as well, or false to not include it in the stream for further handling.
    func callAsFunction(_ input: Input, ifUnavailable: ((ActionExecution) -> Bool)? = nil) {
        do {
            try execute(input)
            ActionExecution.subject.send(.init(sourceIdentifier: sourceIdentifier, actionIdentifier: actionIdentifier, input: input, error: nil))
        } catch {
            _ = ActionExecution.errorsPublisher
            let execution = ActionExecution(sourceIdentifier: sourceIdentifier, actionIdentifier: actionIdentifier, input: input, error: error)
            if let ifUnavailable = ifUnavailable {
                if ifUnavailable(execution) {
                    ActionExecution.subject.send(execution)
                }
            } else {
                ActionExecution.subject.send(execution)
            }
        }
    }
}

public extension Action where Input == Void {
    /// Executes the Action. If a closure is provided as well, then the closure will be called if the Action is unavailable because the underlying Source has deinitialized or is in a different state that doesn't allow this Action. Return true from the closure to propogate the error to the ActionExecution.errors stream as well, or false to not include it in the stream for further handling.
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

    init<T: SourceProtocol>(actionIdentifier: String, source: T, method: @escaping (T) -> (Input) -> Void) {
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

    init<T: SourceProtocol>(actionIdentifier: String, source: T, method: @escaping (T) -> () -> Void) where Input == Void {
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
    func setSourceIfNeeded(_ source: any SourceProtocol)
}

extension Action: IdentifiableAction {
    fileprivate func setSourceIfNeeded(_ source: any SourceProtocol) {
        guard source is DecodableActionSource else { return }
        guard self.source.object == nil else { return }
        guard (source as? DecodableActionSource)?.decodableActionSourceIdentifier == sourceIdentifier else { return }
        self.source.object = source
    }
}

extension Action: CustomStringConvertible, CustomDebugStringConvertible {
    public var debugDescription: String {
        "Action<\(Input.self)>(actionIdentifier: \(actionIdentifier), sourceIdentifier: \(sourceIdentifier))"
    }
}

/// A record of an Action being executed, including the description and input that was used
public struct ActionExecution {
    public static let publisher = subject.eraseToAnyPublisher()
    fileprivate static let subject = PassthroughSubject<ActionExecution, Never>()

    /// A publisher of all ActionExecution errors. If client code retrieves this publisher to subscribe and handle the errors in a custom manner, the default error handling (printing in debug builds) is automatically cancelled
    public static var errors: AnyPublisher<ActionExecution, Never> {
        defer {
            defaultErrorSubscription.clear()
        }
        return errorsPublisher.eraseToAnyPublisher()
    }

    fileprivate static let errorsPublisher = {
        let publisher = ActionExecution.publisher.filter { $0.error != nil }
        defaultErrorSubscription.set(publisher.sink { execution in
            guard let error = execution.error else { return }
            // assert ensures it only runs in non-release builds
            assert({
                print(error)
                return true
            }())
        })
        return publisher
    }()

    private static let defaultErrorSubscription = SubscriptionHandler()

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

fileprivate extension SourceProtocol where Self: DecodableActionSource {
    func setSourceOn(state: Any) {
        if let action = state as? IdentifiableAction {
            action.setSourceIfNeeded(self)
            return
        }
        if state is ReflectionExempt { return }
        return Mirror(reflecting: state).children.forEach { setSourceOn(state: $0.value) }
    }
}

/// A private protocol used for connecting decoded Actions to the correct method on a Source
fileprivate protocol SourceMethodResolving {
    func resolvedMethod<ResolvedInput, ForSource: SourceProtocol>(for source: ForSource, input: ResolvedInput) -> (() -> Void)?
}

extension SourceArchitecture.Source.ActionFromMethod: SourceMethodResolving {
    /// Retrieves the method that should be called by a decoded Action
    fileprivate func resolvedMethod<ResolvedInput, ForSource: SourceProtocol>(for source: ForSource, input: ResolvedInput) -> (() -> Void)? {
        guard let source = source as? Source, let input = input as? Input else { return nil }
        return { method(source)(input) }
    }
}


// MARK: - Private Helper Types -

private protocol Parentable {
    func setParent(_ parent: AnyObject)
}

fileprivate final class Observed<T> {
    @Published fileprivate var state: T! {
        didSet {
            objectDidChange.send(state)
        }
    }
    fileprivate var objectWillChange: Publishers.ReceiveOn<Published<T?>.Publisher, RunLoop> { $state.receive(on: RunLoop.main) }
    fileprivate var objectDidChange = PassthroughSubject<T, Never>()
}

private final class WeakReference {
    weak var object: AnyObject?
    init() { }
}

private final class SubscriptionHandler {
    private var subscription: AnyCancellable?
    func set(_ subscription: AnyCancellable?) {
        self.subscription = subscription
    }
    func clear() {
        subscription?.cancel()
        subscription = nil
    }
}


// MARK: - Reflection Exempt Protocol and Extensions -

/// A protocol for specifying types that shouldn't be reflected through when looking up existing Actions. For example, we don't need to reflect into a child Source, because it already manages its own Actions. Not skipping these types can cause excessive or infinite recursion
fileprivate protocol ReflectionExempt { }

extension AnySource: ReflectionExempt { }
extension SourceArchitecture.Sourced: ReflectionExempt { }
extension SourceArchitecture.Source: ReflectionExempt { }
extension Array: ReflectionExempt where Element: ReflectionExempt { }
extension Set: ReflectionExempt where Element: ReflectionExempt { }
extension Optional: ReflectionExempt where Wrapped: ReflectionExempt { }

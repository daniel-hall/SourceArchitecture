//
//  Action.swift
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


public struct Action<Input> {
    static public var doNothing: Action<Input> {
        .init(identifier: "doNothing") { _ in }
    }
    public let identifier: String
    private let execute: (Input) throws -> Void

    /// Initialize with an arbitrary closure for testing
    internal init(identifier: String = "TestClosure", testClosure: @escaping (Input) throws -> Void) {
        self.identifier = identifier
        self.execute = testClosure
    }

    public func map<NewInput>(transform: @escaping (NewInput) -> Input) -> Action<NewInput> {
        .init(identifier: "MappedAction.From." + self.identifier + "_" + UUID().uuidString) {
            try self.execute(transform($0))
        }
    }
}

public extension Action {
    enum Error: LocalizedError {
        public typealias Identifier = String
        case actionSourceDeinitialized(Identifier)
        case actionExpired(Identifier)

        public var errorDescription: String? {
            switch self {
            case .actionSourceDeinitialized(let identifier): return "Attempted to execute an Action from a Source that was deinitialized and can therefore no longer execute the underlying method. The Action's identifier is: \(identifier)."
            case .actionExpired(let identifier): return "Attempted to execute an expired Action with identifier: \(identifier). Expired Actions are those which were part of a Source's previous model state, but not its current model state."
            }
        }
    }
}

public extension Action {
    func callAsFunction(_ input: Input, ifUnavailable: (Swift.Error) -> Void = _defaultActionUnavailableHandler) {
        do {
            try execute(input)
        } catch {
            ifUnavailable(error)
        }
    }
}

public extension Action where Input == Void {
    func callAsFunction(ifUnavailable: (Swift.Error) -> Void = _defaultActionUnavailableHandler) {
        callAsFunction((), ifUnavailable: ifUnavailable)
    }
}

extension Action: IdentifiableAction { }

extension Action: Equatable {
    public static func == (lhs: Action<Input>, rhs: Action<Input>) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

internal protocol IdentifiableAction {
    var identifier: String { get }
}

extension Optional: IdentifiableAction where Wrapped: IdentifiableAction {
    var identifier: String {
        switch self {
        case .none: return "EmptyOptionalAction"
        case .some(let action): return action.identifier
        }
    }
}

public var _defaultActionUnavailableHandler: (Swift.Error) -> Void = { error in
    // assert ensures it only runs in non-release builds
    assert({
        print(error)
        return true
    }())
}

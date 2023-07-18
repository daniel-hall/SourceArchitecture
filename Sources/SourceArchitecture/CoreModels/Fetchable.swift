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


public enum Fetchable<Value> {
    case fetching(Fetching)
    case fetched(Fetched)
    case failure(Failure)

    public var fetched: Fetched? {
        if case .fetched(let fetched) = self { return fetched }
        return nil
    }

    public var fetching: Fetching? {
        if case .fetching(let fetching) = self { return fetching }
        return nil
    }

    public var failure: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }

    public struct Fetching {
        public let progress: AnySource<Progress>?
        public init(progress: AnySource<Progress>?) {
            self.progress = progress
        }
    }

    public struct Fetched {
        public let refresh: Action<Void>?
        public var value: Value
        public init(value: Value, refresh: Action<Void>?) {
            self.value = value
            self.refresh = refresh
        }
    }

    public struct Failure {
        public let error: Swift.Error
        public let failedAttempts: Int
        public let retry: Action<Void>?
        public init(error: Swift.Error, failedAttempts: Int, retry: Action<Void>?) {
            self.error = error
            self.failedAttempts = failedAttempts
            self.retry = retry
        }
    }
}

public extension Fetchable {
    func map<NewValue>(_ transform: (Value) -> NewValue) -> Fetchable<NewValue> {
        switch self {
        case .fetching(let fetching): return .fetching(.init(progress: fetching.progress))
        case .fetched(let fetched): return .fetched(.init(value: transform(fetched.value), refresh: fetched.refresh))
        case .failure(let failure): return .failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: failure.retry))
        }
    }
}

public extension Fetchable {
    func addingPlaceholder<Placeholder>(_ placeholder: Placeholder) -> FetchableWithPlaceholder<Value, Placeholder> {
        switch self {
        case .fetching(let fetching): return .fetching(.init(placeholder: placeholder, progress: fetching.progress))
        case .failure(let failure): return .failure(.init(placeholder: placeholder, error: failure.error, failedAttempts: failure.failedAttempts, retry: failure.retry))
        case .fetched(let fetched): return .fetched(.init(placeholder: placeholder, value: fetched.value, refresh: fetched.refresh))
        }
    }
}

extension Fetchable: Equatable where Value: Equatable {
    public static func ==(lhs: Fetchable<Value>, rhs: Fetchable<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.fetching(let left), .fetching(let right)):
            return (left.progress == nil) == (right.progress == nil)
        case (.fetched(let left), .fetched(let right)):
            return left.value == right.value
        case (.failure(let left), .failure(let right)):
            return left.error.localizedDescription == right.error.localizedDescription
            && left.failedAttempts == right.failedAttempts
        default: return false
        }
    }
}

public protocol FetchableRepresentable {
    associatedtype Value
    func asFetchable() -> Fetchable<Value>
}

extension Fetchable: FetchableRepresentable {
    public func asFetchable() -> Fetchable<Value> { self }
}

public extension AnySource where Model: FetchableRepresentable {
    // Disfavored overload because if the Model is also FetchableWithPlaceholderRepresentable, we want to prefer that version of mapFetchedValue to preserve the more complete type
    @_disfavoredOverload
    func mapFetchedValue<NewValue>(_ transform: @escaping (Model.Value) -> NewValue) -> AnySource<Fetchable<NewValue>> {
        map { $0.asFetchable().map(transform) }
    }
}

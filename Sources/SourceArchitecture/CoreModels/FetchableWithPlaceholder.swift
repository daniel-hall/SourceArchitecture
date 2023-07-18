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


public enum FetchableWithPlaceholder<Value, Placeholder> {
    case fetching(Fetching)
    case fetched(Fetched)
    case failure(Failure)
    
    public var placeholder: Placeholder {
        switch self {
        case .fetching(let fetching): return fetching.placeholder
        case .fetched(let fetched): return fetched.placeholder
        case .failure(let error): return error.placeholder
        }
    }
    
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
        public let placeholder: Placeholder
        public init(placeholder: Placeholder, progress: AnySource<Progress>?) {
            self.placeholder = placeholder
            self.progress = progress
        }
    }
    
    public struct Fetched {
        public let refresh: Action<Void>?
        public let value: Value
        public let placeholder: Placeholder
        public init(placeholder: Placeholder, value: Value, refresh: Action<Void>?) {
            self.placeholder = placeholder
            self.value = value
            self.refresh = refresh
        }
    }
    
    public struct Failure {
        public let error: Swift.Error
        public let failedAttempts: Int
        public let retry: Action<Void>?
        public let placeholder: Placeholder
        public init(placeholder: Placeholder, error: Swift.Error, failedAttempts: Int, retry: Action<Void>?) {
            self.placeholder = placeholder
            self.error = error
            self.failedAttempts = failedAttempts
            self.retry = retry
        }
    }
}

public extension FetchableWithPlaceholder {
    func map<NewValue>(_ transform: (Value) -> NewValue) -> FetchableWithPlaceholder<NewValue, Placeholder> {
        switch self {
        case .fetching(let fetching): return .fetching(.init(placeholder: fetching.placeholder, progress: fetching.progress))
        case .fetched(let fetched): return .fetched(.init(placeholder: fetched.placeholder, value: transform(fetched.value), refresh: fetched.refresh))
        case .failure(let error): return .failure(.init(placeholder: error.placeholder, error: error.error, failedAttempts: error.failedAttempts, retry: error.retry))
        }
    }
    
    func mapPlaceholder<NewPlaceholder>(_ transform: (Placeholder) -> NewPlaceholder) -> FetchableWithPlaceholder<Value, NewPlaceholder> {
        switch self {
        case .fetching(let fetching): return .fetching(.init(placeholder: transform(fetching.placeholder), progress: fetching.progress))
        case .fetched(let fetched): return .fetched(.init(placeholder: transform(fetched.placeholder), value: fetched.value, refresh: fetched.refresh))
        case .failure(let error): return .failure(.init(placeholder: transform(error.placeholder), error: error.error, failedAttempts: error.failedAttempts, retry: error.retry))
        }
    }
}

extension FetchableWithPlaceholder: HasEqualPlaceholder where Placeholder: Equatable {
    func hasEqualPlaceholder(_ other: Any?) -> Bool {
        self.placeholder == (other as? Placeholder)
    }
}

extension FetchableWithPlaceholder: Identifiable where Placeholder: Identifiable {
    public var id: Placeholder.ID { placeholder.id }
}

extension FetchableWithPlaceholder: Equatable where Value: Equatable {
    fileprivate func placeholderIsEqual(to other: Placeholder?) -> Bool {
        (placeholder is Void) || (self as? HasEqualPlaceholder)?.hasEqualPlaceholder(other) == true
    }
    public static func ==(lhs: FetchableWithPlaceholder<Value, Placeholder>, rhs: FetchableWithPlaceholder<Value, Placeholder>) -> Bool {
        switch (lhs, rhs) {
        case (.fetching(let left), .fetching(let right)):
            return lhs.placeholderIsEqual(to: right.placeholder)
            && (left.progress == nil) == (right.progress == nil)
        case (.fetched(let left), .fetched(let right)):
            return left.value == right.value
            && lhs.placeholderIsEqual(to: right.placeholder)
        case (.failure(let left), .failure(let right)):
            return left.error.localizedDescription == right.error.localizedDescription
            && left.failedAttempts == right.failedAttempts
            && lhs.placeholderIsEqual(to: right.placeholder)
        default: return false
        }
    }
}

extension FetchableWithPlaceholder: FetchableWithPlaceholderRepresentable {
    public func asFetchableWithPlaceholder() -> FetchableWithPlaceholder<Value, Placeholder> { self }
}

extension FetchableWithPlaceholder: FetchableRepresentable {
    public func asFetchable() -> Fetchable<Value> {
        switch self {
        case .fetching(let fetching):
            return .fetching(.init(progress: fetching.progress))
        case .failure(let failure):
            return .failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: failure.retry))
        case .fetched(let fetched):
            return .fetched(.init(value: fetched.value, refresh: fetched.refresh))
        }
    }
}

public protocol FetchableWithPlaceholderRepresentable {
    associatedtype Value
    associatedtype Placeholder
    func asFetchableWithPlaceholder() -> FetchableWithPlaceholder<Value, Placeholder>
}

public extension AnySource where Model: FetchableRepresentable {
    func addingPlaceholder<T>(_ placeholder: T) -> AnySource<FetchableWithPlaceholder<Model.Value, T>> {
        map { $0.asFetchable().addingPlaceholder(placeholder) }
    }
    
    func addingPlaceholder() -> AnySource<FetchableWithPlaceholder<Model.Value, Void>> {
        addingPlaceholder(())
    }
}

public extension AnySource where Model: FetchableWithPlaceholderRepresentable {
    func mapFetchedValue<NewValue>(_ transform: @escaping (Model.Value) -> NewValue) -> AnySource<FetchableWithPlaceholder<NewValue, Model.Placeholder>> {
        map { $0.asFetchableWithPlaceholder().map(transform) }
    }
    
    func mapFetchablePlaceholder<NewPlaceholder>(_ transform: @escaping (Model.Placeholder) -> NewPlaceholder) -> AnySource<FetchableWithPlaceholder<Model.Value, NewPlaceholder>> {
        map { $0.asFetchableWithPlaceholder().mapPlaceholder(transform) }
    }
}

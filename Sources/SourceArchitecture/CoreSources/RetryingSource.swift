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


/// A way of specifying how retries should be executed for Fetched models. The strategy is reset every time the fetch succeeds
public enum RetryStrategy {
    // Retry every time the specified interval elapses, with a maximum number of retries before it stops trying to retry
    case everyIntervalWithMaximum(EveryIntervalWithMaximum)
    // Retry every time the specified interval elapses, with no maximum number of retries (will retry indefinitely)
    case everyIntervalWithoutMaximum(EveryIntervalWithoutMaximum)
    // Retries over and over, but doubles the interval that each successive retry happens after, i.e. 1 second, then 2 seconds, then 4 seconds, then 8 seconds, then 16 seconds, etc.
    case withExponentialBackoff
    
    public struct EveryIntervalWithMaximum {
        let retryInterval: TimeInterval
        let maximumRetries: Int
        public init(retryInterval: TimeInterval, maximumRetries: Int) {
            self.retryInterval = retryInterval
            self.maximumRetries = maximumRetries
        }
    }
    
    public struct EveryIntervalWithoutMaximum {
        let retryInterval: TimeInterval
        public init(retryInterval: TimeInterval) {
            self.retryInterval = retryInterval
        }
    }
}

public enum ForwardErrorAfter {
    case failedAttempts(Int)
    case timeInterval(TimeInterval)
    case never
    case immediately
}

/// A Source that retries using a specified RetryStrategy for as long as its Fetchable model is an .error
private final class RetryingSource<Value>: Source<Fetchable<Value>> {

    @ActionFromMethod(retry) var retryAction
    @Sourced var fetchableValue: Fetchable<Value>

    var interval: TimeInterval
    let maximumRetries: Int?
    var retries = 0
    let shouldUseBackoff: Bool
    let retryStrategy: RetryStrategy
    let forwardAfter: ForwardErrorAfter
    var retryWorkItem: DispatchWorkItem?
    var forwardWorkItem: DispatchWorkItem?

    lazy var initialState = {
        update(model: fetchableValue)
        return state
    }()

    init(_ source: AnySource<Fetchable<Value>>, retryStrategy: RetryStrategy, forwardErrorAfter: ForwardErrorAfter) {
        self.retryStrategy = retryStrategy
        self.forwardAfter = forwardErrorAfter
        switch retryStrategy {
        case .withExponentialBackoff:
            shouldUseBackoff = true
            interval = 1
            maximumRetries = nil
        case .everyIntervalWithMaximum(let strategy):
            shouldUseBackoff = false
            interval = strategy.retryInterval
            maximumRetries = strategy.maximumRetries
        case .everyIntervalWithoutMaximum(let strategy):
            shouldUseBackoff = false
            interval = strategy.retryInterval
            maximumRetries = nil
        }
        _fetchableValue = .init(from: source, updating: RetryingSource.update)
    }
    
    func update(model: Fetchable<Value>) {
        switch model {
        case .fetching:
            retryWorkItem?.cancel()
            forwardWorkItem?.cancel()
            self.state = model
        case .fetched:
            if shouldUseBackoff { interval = 1 }
            retries = 0
            retryWorkItem?.cancel()
            forwardWorkItem?.cancel()
            self.state = model
        case .failure:
            if forwardWorkItem == nil {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, case .failure(let failure) = self.fetchableValue else {
                        return
                    }
                    if case .failure = self.state {
                        return
                    }
                    let model = Fetchable<Value>.failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: self.retryAction))
                    self.state = model
                }
                self.forwardWorkItem = workItem
                if case .timeInterval(let interval) = forwardAfter {
                    DispatchQueue.global().asyncAfter(deadline: .now() + interval, execute: workItem)
                }
            }
            retryWorkItem?.cancel()
            let retry = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.retry()
            }
            retryWorkItem = retry
            switch forwardAfter {
            case .immediately: forwardWorkItem?.perform()
            case .failedAttempts(let failedAttempts) where fetchableValue.failure?.failedAttempts ?? -1 > failedAttempts: forwardWorkItem?.perform()
            default: DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + interval, execute: retry)
            }
        }
    }
    
    func retry() {
        retryWorkItem?.cancel()
        if let maximumRetries = maximumRetries, retries >= maximumRetries { return }
        if case .failure = fetchableValue {
            retries += 1
            if shouldUseBackoff, interval < TimeInterval.greatestFiniteMagnitude / 2  {
                interval = interval * 2
            }
            fetchableValue.failure?.retry?()
        }
    }
    
    func manualRetry() {
        if case .failure(let failure) = fetchableValue {
            retryWorkItem?.cancel()
            forwardWorkItem?.cancel()
            switch retryStrategy {
            case .withExponentialBackoff:
                interval = 1
            case .everyIntervalWithMaximum(let strategy):
                interval = strategy.retryInterval
            case .everyIntervalWithoutMaximum(let strategy):
                interval = strategy.retryInterval
            }
            failure.retry?()
        }
    }
}

public extension AnySource where Model: FetchableWithPlaceholderRepresentable & FetchableRepresentable {
    /// Retries the request for a `Fetchable<Value>` using the specified strategy for as long as there is an error
    func retrying(_ strategy: RetryStrategy, forwardErrorAfter: ForwardErrorAfter = .failedAttempts(3)) -> AnySource<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        RetryingSource(map { $0.asFetchableWithPlaceholder().asFetchable() }, retryStrategy: strategy, forwardErrorAfter: forwardErrorAfter).eraseToAnySource().addingPlaceholder().mapFetchablePlaceholder {
            self.state.asFetchableWithPlaceholder().placeholder
        }
    }
}

public extension AnySource where Model: FetchableRepresentable {
    /// Retries the request for a `Fetchable<Value>` using the specified strategy for as long as there is an error
    @_disfavoredOverload func retrying(_ strategy: RetryStrategy, forwardErrorAfter: ForwardErrorAfter = .failedAttempts(3)) -> AnySource<Fetchable<Model.Value>> {
        RetryingSource(map { $0.asFetchable() }, retryStrategy: strategy, forwardErrorAfter: forwardErrorAfter).eraseToAnySource()
    }
}

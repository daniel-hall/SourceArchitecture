//
//  RetryingSource.swift
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

/// A Source that retries using a specified RetryStrategy for as long as its Fetched model is an .error
final class RetryingSource<Value>: Source<Fetchable<Value>>, ActionSource {
    
    struct Actions: ActionMethods {
        var retry = ActionMethod(RetryingSource.retry)
    }
    
    private var interval: TimeInterval
    private let maximumRetries: Int?
    private var retries = 0
    private let shouldUseBackoff: Bool
    private let retryStrategy: RetryStrategy
    private let forwardAfter: ForwardErrorAfter
    private var retryWorkItem: DispatchWorkItem?
    private var forwardWorkItem: DispatchWorkItem?
    private let source: Source<Fetchable<Value>>
    private let state: State
    
    init(_ source: Source<Fetchable<Value>>, retryStrategy: RetryStrategy, forwardErrorAfter: ForwardErrorAfter) {
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
        self.source = source
        let state = State(model: source.model)
        self.state = state
        super.init(state)
        source.subscribe(self, method: RetryingSource.update)
    }
    
    private func update() {
        switch source.model {
        case .fetching:
            retryWorkItem?.cancel()
            forwardWorkItem?.cancel()
            state.setModel(source.model)
        case .fetched:
            if shouldUseBackoff { interval = 1 }
            retries = 0
            retryWorkItem?.cancel()
            forwardWorkItem?.cancel()
            state.setModel(source.model)
        case .failure:
            if forwardWorkItem == nil {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, case .failure(let failure) = self.source.model else {
                        return
                    }
                    if case .failure = self.model {
                        return
                    }
                    let model = Fetchable<Value>.failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: self.state.retry))
                    self.state.setModel(model)
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
            case .failedAttempts(let failedAttempts) where source.model.failure?.failedAttempts ?? -1 > failedAttempts: forwardWorkItem?.perform()
            default: DispatchQueue.global(qos: .default).asyncAfter(deadline: .now() + interval, execute: retry)
            }
        }
    }
    
    private func retry() {
        retryWorkItem?.cancel()
        if let maximumRetries = maximumRetries, retries >= maximumRetries { return }
        if case .failure = source.model {
            retries += 1
            if shouldUseBackoff, interval < TimeInterval.greatestFiniteMagnitude / 2  {
                interval = interval * 2
            }
            try? source.model.failure?.retry?()
        }
    }
    
    private func manualRetry() {
        if case .failure(let failure) = source.model {
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
            try? failure.retry?()
        }
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable & FetchableRepresentable {
    func retrying(_ strategy: RetryStrategy, forwardErrorAfter: ForwardErrorAfter = .failedAttempts(3)) -> Source<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        RetryingSource(map { $0.asFetchable() }, retryStrategy: strategy, forwardErrorAfter: forwardErrorAfter).addingPlaceholder().mapFetchablePlaceholder {
            self.model.asFetchableWithPlaceholder().placeholder
        }
    }
}

public extension Source where Model: FetchableRepresentable {
    @_disfavoredOverload func retrying(_ strategy: RetryStrategy, forwardErrorAfter: ForwardErrorAfter = .failedAttempts(3)) -> Source<Fetchable<Model.Value>> {
        RetryingSource(map { $0.asFetchable() }, retryStrategy: strategy, forwardErrorAfter: forwardErrorAfter)
    }
}

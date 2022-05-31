//
//  CombinedFetchableSource.swift
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


/// A Source that combines the result of two model states of Fetchable values. The CombinedFetchable source model will be .fetching if either input is still fetching, .error if either input returns an .error state, or will be .found if BOTH inputs are in a .found state.
final class CombinedFetchableSource<First, Second>: CustomSource {
    class Actions: ActionMethods {
        var refresh = ActionMethod(CombinedFetchableSource.refresh)
        var retry = ActionMethod(CombinedFetchableSource.retry)
    }
    class Threadsafe: ThreadsafeProperties {
        var isRetrying = false
        var firstHasRefreshed = true
        var secondHasRefreshed = false
    }
    private let first: Source<Fetchable<First>>
    private let second: Source<Fetchable<Second>>
    lazy var defaultModel: Fetchable<(First, Second)> = {
        first.subscribe(self, method: CombinedFetchableSource.updateFirst)
        second.subscribe(self, method: CombinedFetchableSource.updateSecond)
        return model
    }()

    init(first: Source<Fetchable<First>>, second: Source<Fetchable<Second>>) {
        self.first = first
        self.second = second
        super.init()
    }

    func updateFirst(value: Fetchable<First>) {
        switch value {
        case .fetched, .failure: threadsafe.firstHasRefreshed = true
        default: break
        }
        updateIfNeeded()
    }

    func updateSecond(value: Fetchable<Second>) {
        switch value {
        case .fetched, .failure: threadsafe.secondHasRefreshed = true
        default: break
        }
        updateIfNeeded()
    }

    func updateIfNeeded() {
        switch (first.model, second.model) {
        case (.fetching(let firstFetching), .fetching(let secondFetching)):
            let combinedProgress: Source<Progress>?
            if let firstProgress = firstFetching.progress, let secondProgress = secondFetching.progress {
                combinedProgress = firstProgress.combined(with: secondProgress).map {
                    let combinedEstimate = ($0.estimatedTimeRemaining, $1.estimatedTimeRemaining)
                    return .init(totalUnits: $0.totalUnits + $1.totalUnits, completedUnits: $0.completedUnits + $1.completedUnits, fractionCompleted: ($0.fractionCompleted + $1.fractionCompleted)/2, estimatedTimeRemaining: combinedEstimate.0.map { first in combinedEstimate.1.map { second in first + second } } ?? combinedEstimate.0 ?? combinedEstimate.1)
                }
            } else {
                combinedProgress = firstFetching.progress ?? secondFetching.progress
            }
            model = .fetching(.init(progress: combinedProgress))
        case (.fetched(let firstFetched), .fetched(let secondFetched)):
            let firstHasRefreshed = threadsafe.firstHasRefreshed
            let secondHasRefreshed = threadsafe.secondHasRefreshed
            guard firstHasRefreshed && secondHasRefreshed else { return }
            model = .fetched(.init(value: (firstFetched.value, secondFetched.value), refresh: actions.refresh))
        case (.failure(let failure), _):
            if case .failure(let existing) = model, existing.error.localizedDescription == failure.error.localizedDescription && existing.failedAttempts == failure.failedAttempts {
                return
            }
            model = .failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: actions.retry))
        case (_, .failure(let failure)):
            if case .failure(let existing) = model, existing.error.localizedDescription == failure.error.localizedDescription && existing.failedAttempts == failure.failedAttempts {
                return
            }
            model = .failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: actions.retry))
        case (.fetching(let fetching), _):
            if case .fetching = model { return }
            model = .fetching(.init(progress: fetching.progress))
        case (_, .fetching(let fetching)):
            if case .fetching = model { return }
            model = .fetching(.init(progress: fetching.progress))
        }
    }

    func retry() {
        second.model.failure?.retry?()
        first.model.failure?.retry?()
    }

    func refresh() {
        if case (.fetched(let first), .fetched(let second)) = (first.model, second.model) {
            threadsafe.firstHasRefreshed = false
            threadsafe.secondHasRefreshed = false
            first.refresh()
            second.refresh()
        }
    }
}


public extension Source where Model: FetchableWithPlaceholderRepresentable & FetchableRepresentable {
    func combinedFetch<Value>(with source: Source<Fetchable<Value>>) -> Source<FetchableWithPlaceholder<(Model.Value, Value), Model.Placeholder>> {
        (combinedFetch(with: source) as Source<Fetchable<(Model.Value, Value)>>).addingPlaceholder(self.model.asFetchableWithPlaceholder().placeholder)
    }
    
    func combinedFetch<Value, Placeholder>(with source: Source<FetchableWithPlaceholder<Value, Placeholder>>) -> Source<FetchableWithPlaceholder<(Model.Value, Value), (Model.Placeholder, Placeholder)>> {
        CombinedFetchableSource(first: map { $0.asFetchable() }, second: source.map { $0.asFetchable() }).eraseToSource().addingPlaceholder((self.model.asFetchableWithPlaceholder().placeholder, source.model.asFetchableWithPlaceholder().placeholder))
    }
    
    func combinedFetch<Value, Placeholder>(with source: Source<FetchableWithPlaceholder<Value, Placeholder>>) -> Source<FetchableWithPlaceholder<(Model.Value, Value), Model.Placeholder>> where Placeholder == Model.Placeholder {
        CombinedFetchableSource(first: map { $0.asFetchable() }, second: source.map { $0.asFetchable() }).eraseToSource().addingPlaceholder(self.model.asFetchableWithPlaceholder().placeholder)
    }
}

public extension Source where Model: FetchableRepresentable {
    @_disfavoredOverload func combinedFetch<Value>(with source: Source<Fetchable<Value>>) -> Source<Fetchable<(Model.Value, Value)>> {
        CombinedFetchableSource(first: map { $0.asFetchable() }, second: source).eraseToSource()
    }
}

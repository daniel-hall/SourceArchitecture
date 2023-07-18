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


/// A Source that combines the result of two model states of Fetchable values. The CombinedFetchable source model will be .fetching if either input is still fetching, .error if either input returns an .error state, or will be .found if BOTH inputs are in a .found state.
private final class CombinedFetchableSource<First, Second>: Source<Fetchable<(First, Second)>> {

    @ActionFromMethod(refresh) var refreshAction
    @ActionFromMethod(retry) var retryAction

    @Threadsafe var isRetrying = false
    @Threadsafe var firstHasRefreshed = true
    @Threadsafe var secondHasRefreshed = false

    @Sourced var first: Fetchable<First>
    @Sourced var second: Fetchable<Second>

    lazy var initialState: Fetchable<(First, Second)> = .fetching(.init(progress: nil))

    init(first: AnySource<Fetchable<First>>, second: AnySource<Fetchable<Second>>) {
        _first = .init(from: first, updating: CombinedFetchableSource.updateFirst)
        _second = .init(from: second, updating: CombinedFetchableSource.updateSecond)
    }

    func onStart() {
        updateIfNeeded()
    }

    func updateFirst(value: Fetchable<First>) {
        switch value {
        case .fetched, .failure: firstHasRefreshed = true
        default: break
        }
        updateIfNeeded()
    }

    func updateSecond(value: Fetchable<Second>) {
        switch value {
        case .fetched, .failure: secondHasRefreshed = true
        default: break
        }
        updateIfNeeded()
    }

    func updateIfNeeded() {
        switch (first, second) {
        case (.fetching(let firstFetching), .fetching(let secondFetching)):
            let combinedProgress: AnySource<Progress>?
            if let firstProgress = firstFetching.progress, let secondProgress = secondFetching.progress {
                combinedProgress = firstProgress.combined(with: secondProgress).map {
                    let combinedEstimate = ($0.estimatedTimeRemaining, $1.estimatedTimeRemaining)
                    return .init(totalUnits: $0.totalUnits + $1.totalUnits, completedUnits: $0.completedUnits + $1.completedUnits, fractionCompleted: ($0.fractionCompleted + $1.fractionCompleted)/2, estimatedTimeRemaining: combinedEstimate.0.map { first in combinedEstimate.1.map { second in first + second } } ?? combinedEstimate.0 ?? combinedEstimate.1)
                }
            } else {
                combinedProgress = firstFetching.progress ?? secondFetching.progress
            }
            state = .fetching(.init(progress: combinedProgress))
        case (.fetched(let firstFetched), .fetched(let secondFetched)):
            let firstHasRefreshed = firstHasRefreshed
            let secondHasRefreshed = secondHasRefreshed
            guard firstHasRefreshed && secondHasRefreshed else {
                return
            }
            state = .fetched(.init(value: (firstFetched.value, secondFetched.value), refresh: refreshAction))
        case (.failure(let failure), _):
            if case .failure(let existing) = state, existing.error.localizedDescription == failure.error.localizedDescription && existing.failedAttempts == failure.failedAttempts {
                return
            }
            state = .failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: retryAction))
        case (_, .failure(let failure)):
            if case .failure(let existing) = state, existing.error.localizedDescription == failure.error.localizedDescription && existing.failedAttempts == failure.failedAttempts {
                return
            }
            state = .failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: retryAction))
        case (.fetching(let fetching), _):
            if case .fetching = state {
                return
            }
            state = .fetching(.init(progress: fetching.progress))
        case (_, .fetching(let fetching)):
            if case .fetching = state {
                return
            }
            state = .fetching(.init(progress: fetching.progress))
        }
    }

    func retry() {
        second.failure?.retry?()
        first.failure?.retry?()
    }

    func refresh() {
        if case (.fetched(let first), .fetched(let second)) = (first, second) {
            firstHasRefreshed = false
            secondHasRefreshed = false
            first.refresh?()
            second.refresh?()
        }
    }
}


public extension AnySource where Model: FetchableWithPlaceholderRepresentable & FetchableRepresentable {
    func combinedFetch<Value>(with source: AnySource<Fetchable<Value>>) -> AnySource<FetchableWithPlaceholder<(Model.Value, Value), Model.Placeholder>> {
        (combinedFetch(with: source) as AnySource<Fetchable<(Model.Value, Value)>>).addingPlaceholder(self.state.asFetchableWithPlaceholder().placeholder)
    }
    
    func combinedFetch<Value, Placeholder>(with source: AnySource<FetchableWithPlaceholder<Value, Placeholder>>) -> AnySource<FetchableWithPlaceholder<(Model.Value, Value), (Model.Placeholder, Placeholder)>> {
        CombinedFetchableSource(first: map { $0.asFetchable() }, second: source.map { $0.asFetchable() }).eraseToAnySource().addingPlaceholder((self.state.asFetchableWithPlaceholder().placeholder, source.state.asFetchableWithPlaceholder().placeholder))
    }
    
    func combinedFetch<Value, Placeholder>(with source: AnySource<FetchableWithPlaceholder<Value, Placeholder>>) -> AnySource<FetchableWithPlaceholder<(Model.Value, Value), Model.Placeholder>> where Placeholder == Model.Placeholder {
        CombinedFetchableSource(first: map { $0.asFetchable() }, second: source.map { $0.asFetchable() }).eraseToAnySource().addingPlaceholder(self.state.asFetchableWithPlaceholder().placeholder)
    }
}

public extension AnySource where Model: FetchableRepresentable {
    @_disfavoredOverload func combinedFetch<Value>(with source: AnySource<Fetchable<Value>>) -> AnySource<Fetchable<(Model.Value, Value)>> {
        CombinedFetchableSource(first: map { $0.asFetchable() }, second: source).eraseToAnySource()
    }
}

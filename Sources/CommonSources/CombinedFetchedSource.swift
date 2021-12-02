//
//  CombinedFetchedSource.swift
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


/// A Source that combines the result of two Source of Fetched values. The CombinedFetchedSource model will be .fetching if either Source is still fetching, .error if either Source returns an .error state, or will be .found if BOTH input Sources are in a .found state.
final class CombinedFetchedSource<First, Second>: Source<Fetchable<(First, Second)>>, ActionSource {
    struct Actions: ActionMethods {
        var refresh = ActionMethod(CombinedFetchedSource.refresh)
        var retry = ActionMethod(CombinedFetchedSource.retry)
    }
    struct MutableProperties {
        var isRetrying = false
        var firstHasRefreshed = true
        var secondHasRefreshed = false
    }
    let first: Source<Fetchable<First>>
    let second: Source<Fetchable<Second>>
    let state: MutableState<MutableProperties>
    
    init(firstSource: Source<Fetchable<First>>, secondSource: Source<Fetchable<Second>>) {
        first = firstSource
        second = secondSource
        
        state = .init(mutableProperties: .init(), model: .fetching(.init(progress: nil)))
        super.init(state)
        first.subscribe(self, method: CombinedFetchedSource.updateFirst)
        second.subscribe(self, method: CombinedFetchedSource.updateSecond)
    }
    
    private func updateFirst() {
        switch first.model {
        case .fetched, .failure:state.firstHasRefreshed = true
        default: break
        }
        updateIfNeeded()
    }
    
    private func updateSecond() {
        switch second.model {
        case .fetched, .failure:state.secondHasRefreshed = true
        default: break
        }
        updateIfNeeded()
    }
    
    private func updateIfNeeded() {
        switch (first.model, second.model) {
        case (.fetching(let first), .fetching(let second)):
            let combinedProgress: Source<Progress>?
            if let first = first.progress, let second = second.progress {
                combinedProgress = first.combined(with: second).map {
                    let combinedEstimate = ($0.estimatedTimeRemaining, $1.estimatedTimeRemaining)
                    return .init(totalUnits: $0.totalUnits + $1.totalUnits, completedUnits: $0.completedUnits + $1.completedUnits, fractionCompleted: ($0.fractionCompleted + $1.fractionCompleted)/2, estimatedTimeRemaining: combinedEstimate.0.map { first in combinedEstimate.1.map { second in first + second } } ?? combinedEstimate.0 ?? combinedEstimate.1)
                }
            } else {
                combinedProgress = first.progress ?? second.progress
            }
            state.setModel(.fetching(.init(progress: combinedProgress)))
        case (.fetched(let first), .fetched(let second)):
            let firstHasRefreshed = state.firstHasRefreshed
            let secondHasRefreshed = state.secondHasRefreshed
            guard firstHasRefreshed && secondHasRefreshed else { return }
            state.setModel(.fetched(.init(value: (first.value, second.value), refresh: state.action(\.refresh))))
        case (.failure(let failure), _):
            if case .failure(let existing) = model, existing.error.localizedDescription == failure.error.localizedDescription && existing.failedAttempts == failure.failedAttempts {
                return
            }
            state.setModel(.failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: state.action(\.retry))))
        case (_, .failure(let failure)):
            if case .failure(let existing) = model, existing.error.localizedDescription == failure.error.localizedDescription && existing.failedAttempts == failure.failedAttempts {
                return
            }
            state.setModel(.failure(.init(error: failure.error, failedAttempts: failure.failedAttempts, retry: state.action(\.retry))))
        case (.fetching(let fetching), _):
            if case .fetching = model { return }
            state.setModel(.fetching(.init(progress: fetching.progress)))
        case (_, .fetching(let fetching)):
            if case .fetching = model { return }
            state.setModel(.fetching(.init(progress: fetching.progress)))
        }
    }
    
    private func retry() {
        try? second.model.failure?.retry?()
        try? first.model.failure?.retry?()
    }
    
    private func refresh() {
        if case (.fetched(let first), .fetched(let second)) = (first.model, second.model) {
            state.firstHasRefreshed = false
            state.secondHasRefreshed = false
            try? first.refresh()
            try? second.refresh()
        }
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable & FetchableRepresentable {
    func combinedFetch<Value>(with source: Source<Fetchable<Value>>) -> Source<FetchableWithPlaceholder<(Model.Value, Value), Model.Placeholder>> {
        (combinedFetch(with: source) as Source<Fetchable<(Model.Value, Value)>>).addingPlaceholder(self.model.asFetchableWithPlaceholder().placeholder)
    }
    
    func combinedFetch<Value, Placeholder>(with source: Source<FetchableWithPlaceholder<Value, Placeholder>>) -> Source<FetchableWithPlaceholder<(Model.Value, Value), (Model.Placeholder, Placeholder)>> {
        CombinedFetchedSource(firstSource: map { $0.asFetchable() }, secondSource: source.map { $0.asFetchable() }).addingPlaceholder((self.model.asFetchableWithPlaceholder().placeholder, source.model.asFetchableWithPlaceholder().placeholder))
    }
    
    func combinedFetch<Value, Placeholder>(with source: Source<FetchableWithPlaceholder<Value, Placeholder>>) -> Source<FetchableWithPlaceholder<(Model.Value, Value), Model.Placeholder>> where Placeholder == Model.Placeholder {
        CombinedFetchedSource(firstSource: map { $0.asFetchable() }, secondSource: source.map { $0.asFetchable() }).addingPlaceholder(self.model.asFetchableWithPlaceholder().placeholder)
    }
}

public extension Source where Model: FetchableRepresentable {
    @_disfavoredOverload func combinedFetch<Value>(with source: Source<Fetchable<Value>>) -> Source<Fetchable<(Model.Value, Value)>> {
        CombinedFetchedSource(firstSource: map { $0.asFetchable() }, secondSource: source)
    }
}

//
//  AfterDelaySource.swift
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

private final class FetchAfterDelaySource<Model>: SourceOf<Fetchable<Model>> {

    fileprivate var initialModel: Fetchable<Model> = .fetching(.init(progress: nil))
    @Source private var fetchable: Fetchable<Model>

    fileprivate init(fetchable: Source<Fetchable<Model>>, delay: TimeInterval) {
        _fetchable = fetchable
        super.init()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            if let self = self {
                fetchable.subscribe(self, method: FetchAfterDelaySource.update)
            }
        }
    }

    private func update(_ value: Fetchable<Model>) {
        model = value
    }
}

public extension Source where Model: FetchableRepresentable {
    @_disfavoredOverload
    func fetchAfterDelay(of numberOfSeconds: TimeInterval) -> Source<Fetchable<Model.Value>> {
        FetchAfterDelaySource(fetchable: self.map { $0.asFetchable() }, delay: numberOfSeconds).eraseToSource()
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable {
    func fetchAfterDelay(of numberOfSeconds: TimeInterval) -> Source<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        FetchAfterDelaySource(fetchable: self.map { $0.asFetchableWithPlaceholder().asFetchable() }, delay: numberOfSeconds).eraseToSource().addingPlaceholder(model.asFetchableWithPlaceholder().placeholder)
    }
}

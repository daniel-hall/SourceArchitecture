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

private final class FetchAfterDelaySource<Model>: Source<Fetchable<Model>> {

    fileprivate var initialState: Fetchable<Model> = .fetching(.init(progress: nil))
    @Sourced(updating: update) private var fetchable: Fetchable<Model>?

    fileprivate init(fetchable: AnySource<Fetchable<Model>>, delay: TimeInterval) {
        super.init()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            if let self = self {
                self._fetchable.setSource(fetchable)
            }
        }
    }

    private func update(_ value: Fetchable<Model>) {
        state = value
    }
}

public extension AnySource where Model: FetchableRepresentable {
    @_disfavoredOverload
    func fetchAfterDelay(of numberOfSeconds: TimeInterval) -> AnySource<Fetchable<Model.Value>> {
        FetchAfterDelaySource(fetchable: self.map { $0.asFetchable() }, delay: numberOfSeconds).eraseToAnySource()
    }
}

public extension AnySource where Model: FetchableWithPlaceholderRepresentable {
    func fetchAfterDelay(of numberOfSeconds: TimeInterval) -> AnySource<FetchableWithPlaceholder<Model.Value, Model.Placeholder>> {
        FetchAfterDelaySource(fetchable: self.map { $0.asFetchableWithPlaceholder().asFetchable() }, delay: numberOfSeconds).eraseToAnySource().addingPlaceholder(state.asFetchableWithPlaceholder().placeholder)
    }
}

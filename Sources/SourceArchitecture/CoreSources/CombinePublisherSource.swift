//
//  Created by Daniel Hall on 5/10/23.
//  Copyright © 2023 Tinder. All rights reserved.
//

import Foundation
import Combine


/// Provides a way to create a Source out of any Combine Publisher
final private class CombinePublisherSource<Input: Publisher>: Source<Input.Output> {
    let initialState: Model
    let input: Input
    var subscription: AnyCancellable?
    init(_ publisher: Input, initialModel: Model) {
        input = publisher
        self.initialState = initialModel
        super.init()
        subscription = input.sink(receiveCompletion: { _ in } , receiveValue: { [weak self] in self?.state = $0 })
    }
}

public extension Publisher {
    func eraseToSource(initialValue: Output) -> AnySource<Output> {
        CombinePublisherSource(self, initialModel: initialValue).eraseToAnySource()
    }
}

private class PublishedWrapper<Value> {
    @Published var value: Value
    init(_ published: Published<Value>) {
        _value = published
    }
}

public extension Published {
    mutating func eraseToAnySource() -> AnySource<Value> {
        let published = PublishedWrapper(self)
        return CombinePublisherSource(self.projectedValue, initialModel: published.value).eraseToAnySource()
    }
}

public extension CurrentValueSubject {
    func eraseToSource() -> AnySource<Output> {
        CombinePublisherSource(self, initialModel: value).eraseToAnySource()
    }
}

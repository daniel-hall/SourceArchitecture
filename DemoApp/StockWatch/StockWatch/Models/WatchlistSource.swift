//
//  WatchlistSource.swift
//  StockWatch
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
import SourceArchitecture


struct Watchlist {
    let watchedSymbols: Array<StockSymbol>
    let add: Action<StockSymbol>
    let remove: Action<StockSymbol>
    let toggle: Action<StockSymbol>
}

final class WatchlistSource: Source<Watchlist>, ActionSource {

    struct Actions: ActionMethods {
        fileprivate var add = ActionMethod(WatchlistSource.add)
        fileprivate var remove = ActionMethod(WatchlistSource.remove)
        fileprivate var toggle = ActionMethod(WatchlistSource.toggle)
    }

    typealias Dependencies = FileDependency
    private let dependencies: Dependencies
    private let state: State
    private let file: Source<Persistable<Array<StockSymbol>>>
    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.file = dependencies.fileResource(WatchlistResource())
        let state = State(model: .init(watchedSymbols: [], add: .noOp(), remove: .noOp(), toggle: .noOp()))
        self.state = state
        super.init(state)
        file.subscribe(self, method: WatchlistSource.update)
    }

    private func update() {
        state.setModel(.init(watchedSymbols: file.model.found?.value ?? [], add: state.action(\.add), remove: state.action(\.remove), toggle: state.action(\.toggle)))
    }

    private func add(symbol: StockSymbol) {
        let source = WatchedSymbolSource(dependencies: dependencies, symbol: symbol)
        try? source.model.set(symbol)
    }

    private func remove(symbol: StockSymbol) {
        let source = WatchedSymbolSource(dependencies: dependencies, symbol: symbol)
        try? source.model.clear?()
    }

    private func toggle(symbol: StockSymbol) {
        if model.watchedSymbols.contains(symbol) {
            remove(symbol: symbol)
        } else {
            add(symbol: symbol)
        }
    }
}

private struct WatchlistResource: FileResource {
    typealias Value = Array<StockSymbol>
    let filePath = "com.StockWatch.Watchlist"
}

public final class WatchedSymbolSource: Source<Persistable<StockSymbol>> {
    typealias Dependencies = FileDependency
    init(dependencies: Dependencies, symbol: StockSymbol) {
        super.init(dependencies.fileResourceElement(WatchlistSymbolResource(symbol: symbol)))
    }
}

private struct WatchlistSymbolResource: ResourceElement {
    typealias Value = StockSymbol
    let parentResource = WatchlistResource()
    let symbol: StockSymbol
    var elementIdentifier: String { symbol.symbol }

    func set(element: StockSymbol?) -> (Array<StockSymbol>?) throws -> Array<StockSymbol> {
        if let symbol = element {
            guard symbol == self.symbol else { return { $0 ?? [] } }
            return {
                let existing = $0 ?? []
                if existing.contains(symbol) {
                    return existing
                }
                return (existing + [symbol])
            }
        } else {
            return {
                var array = $0 ?? []
                array.removeAll { $0 == self.symbol }
                return array
            }
        }
    }

    func getElement(from value: Array<StockSymbol>) throws -> StockSymbol? {
        value.first { $0 == symbol }
    }
}


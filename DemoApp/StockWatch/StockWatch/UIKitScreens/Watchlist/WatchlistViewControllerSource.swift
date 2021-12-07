//
//  WatchlistViewControllerSource.swift
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

import SourceArchitecture
import Foundation


final class WatchlistViewControllerSource: SyncedSource<WatchlistViewController.RenderedModel>, ActionSource, CacheResource {
    
    struct Actions: ActionMethods {
        fileprivate var unwatch = ActionMethod(WatchlistViewControllerSource.unwatch)
        fileprivate var select = ActionMethod(WatchlistViewControllerSource.select)
    }
    
    struct MutableProperties: SyncedSourcePropertiesProvider {
        var syncProperties = SyncedSourceProperties()
    }
    
    typealias Dependencies = WatchlistSource.Dependencies & WatchedStockCellSource.Dependencies & SelectedSymbolSource.Dependencies
    let cacheIdentifier = "WatchlistViewControllerSource"
    private let dependencies: Dependencies
    private let selected: SelectedSymbolSource
    private let watchlist: WatchlistSource
    private let state: MutableState<MutableProperties>
    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.state = .init(mutableProperties: .init(), model: .init(watchedStocks: [], unwatch: .noOp, select: .noOp))
        selected = SelectedSymbolSource(dependencies: dependencies)
        watchlist = WatchlistSource(dependencies: dependencies)
        super.init(state, dependencies: dependencies)
        watchlist.subscribe(self, method: WatchlistViewControllerSource.update)
    }
    
    private func update() {
        state.setModel(WatchlistViewController.RenderedModel(watchedStocks: watchlist.model.watchedSymbols.map { WatchedStockCellSource(dependencies: dependencies, symbol: $0) }, unwatch: state.unwatch, select: state.select))
    }
    
    private func unwatch(symbol: WatchedStockCell.RenderedModel.Placeholder) {
        watchlist.model.watchedSymbols.first { $0.symbol == symbol.symbol }.map { try? watchlist.model.remove($0) }
    }
    
    private func select(symbol: WatchedStockCell.RenderedModel.Placeholder) {
        watchlist.model.watchedSymbols.first { $0.symbol == symbol.symbol }.map { try? selected.model.set($0) }
    }
}

final class WatchedStockCellSource: Source<WatchedStockCell.RenderedModel> {
    typealias Dependencies = StockQuoteSource.Dependencies
    init(dependencies: Dependencies, symbol: StockSymbol) {
        let quoteSource = StockQuoteSource(dependencies: dependencies, symbol: symbol)
        super.init {
            quoteSource.mapFetchedValue {
                WatchedStockCell.Model(price: $0.price, percentChange: $0.changePercent, amountChange: $0.changeAmount, trend: $0.changeAmount.hasPrefix("-") ? .down : .up, lastUpdatedDate: $0.timestamp)
            }
            .refreshing(every: 5)
            .retrying(.withExponentialBackoff, forwardErrorAfter: .never)
            .addingPlaceholder(WatchedStockCell.Placeholder(symbol: symbol.symbol, name: symbol.name))
        }
    }
}

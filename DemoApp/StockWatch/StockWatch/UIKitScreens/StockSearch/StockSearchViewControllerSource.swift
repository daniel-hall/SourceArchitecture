//
//  StockSearchViewControllerSource.swift
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


/// This Source subclasses SyncedSource, which means that by specifying a cache identifier, all instances of this Source that are created independently anywhere in the app will always be synced to have the same model value.  If any of those instances change their model, all others will update as well.  Note how that typing a search term in either the UIKit screen or the SwiftUI screen and then switching to the other will show he same search term and results already in place. See unit tests for more examples
final class StockSearchViewControllerSource: SyncedSource<StockSearchViewController.RenderedModel>, ActionSource, CacheResource {
    struct Actions: ActionMethods {
        var search = ActionMethod(StockSearchViewControllerSource.search)
    }
    typealias Dependencies = StockSymbolsSource.Dependencies & StockSearchCellSource.Dependencies
    private struct MutableProperties: SyncedSourcePropertiesProvider {
        var syncProperties = SyncedSourceProperties()
        var searchTerm: String?
    }
    let cacheIdentifier = "StockSearchViewControllerSource"
    private let symbols: StockSymbolsSource
    private let state: MutableState<MutableProperties>
    private let dependencies: Dependencies
    
    init(dependencies: Dependencies) {
        let symbols = StockSymbolsSource(dependencies: dependencies)
        state = .init(mutableProperties: .init()) { state in
            symbols.model.map { symbols in
                StockSearchViewController.Model(searchTerm: nil, symbols: symbols.map {
                    StockSearchCellSource(dependencies: dependencies, symbol: $0)
                }, search: state.search) }
        }
        self.symbols = symbols
        self.dependencies = dependencies
        super.init(state, dependencies: dependencies)
        self.symbols.subscribe(self, method: StockSearchViewControllerSource.update)
    }
    
    private func update() {
        let searchTerm = state.searchTerm
        state.setModel(
            symbols.model.map { symbols in
                let filtered = searchTerm.flatMap { $0.isEmpty ? nil : $0.lowercased() }
                    .map { term in
                        var (filtered, remaining) = symbols.reduce(into: ([StockSymbol](), [StockSymbol]())) {
                            if $1.symbol.lowercased().hasPrefix(term) {
                                $0.0.append($1)
                            } else { $0.1.append($1) }
                        }
                        (filtered, remaining) = remaining.reduce(into: (filtered, [StockSymbol]())) {
                            if $1.name.lowercased().hasPrefix(term) {
                                $0.0.append($1)
                            } else { $0.1.append($1) }
                        }
                        (filtered, remaining) = remaining.reduce(into: (filtered, [StockSymbol]())) {
                            if $1.symbol.lowercased().contains(term) {
                                $0.0.append($1)
                            } else { $0.1.append($1) }
                        }
                        (filtered, remaining) = remaining.reduce(into: (filtered, [StockSymbol]())) {
                            if $1.name.lowercased().contains(term) {
                                $0.0.append($1)
                            } else { $0.1.append($1) }
                        }
                        return filtered
                    } ?? symbols
                return StockSearchViewController.Model(searchTerm: searchTerm, symbols: filtered.map { StockSearchCellSource(dependencies: self.dependencies, symbol: $0) }, search: state.search)
            }
        )
    }
    
    private func search(for term: String?) {
        state.searchTerm = term
        self.update()
    }
}

private var selected: SelectedSymbolSource!

final class StockSearchCellSource: Source<StockSearchCell.RenderedModel> {
    typealias Dependencies = WatchedSymbolSource.Dependencies & StockQuoteSource.Dependencies & CacheDependency
    init(dependencies: Dependencies, symbol: StockSymbol) {
        if selected == nil {
            selected = SelectedSymbolSource(dependencies: dependencies)
        }
        super.init {
            connectable(placeholder: .init(symbol: symbol.symbol, name: symbol.name)) {
                WatchedSymbolSource(dependencies: dependencies, symbol: symbol)
                    .combined(with: StockQuoteSource(dependencies: dependencies, symbol: symbol))
                    .map { watched, quote in
                        let isWatchlisted = watched.found != nil
                        return quote.map { StockSearchCell.Model(price: $0.price, lastUpdatedDate: $0.timestamp) }
                        .mapPlaceholder { _ in  StockSearchCell.Placeholder(isWatchlisted: isWatchlisted, toggleWatched: isWatchlisted ? watched.found!.clear : watched.set.map { symbol }, select: selected.model.set.map { symbol })
                        }
                    }
            }
            .onConnect {
                $0.refreshing(every: 5)
                    .retrying(.withExponentialBackoff, forwardErrorAfter: .never)
            }
        }
    }
}

//
//  StockSearchViewSource.swift
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


// We can map the existing Source for the UIKit StockSearchViewController into the Source needed for the SwiftUI StockSearchView. This maintains the same single source of truth across both versions of the screen and means we don't need to change any underlying implementations of business logic, just convert the resulting models. Note that because "StockSearchViewControllerSource" holds all of its state in core dependencies like Cache, File and UserDefaults, we can instantiate a new copy of it here and it will still be fully in-sync with the UIKit instance of "StockSearchViewControllerSource" that is driving the UIKit screen implementation.
final class StockSearchViewSource: Source<StockSearchView.RenderedModel> {
    typealias Dependencies = StockSearchViewControllerSource.Dependencies
    init(dependencies: Dependencies) {
        super.init {
            StockSearchViewControllerSource(dependencies: dependencies).mapFetchedValue { stockSearchViewControllerModel in
                let mappedCellModels: [Source<StockCellView.RenderedModel>] = stockSearchViewControllerModel.symbols.map {
                    $0.mapConnectedValue {
                        $0.map { StockCellView.Model(price: $0.price, lastUpdatedDate: $0.lastUpdatedDate) }
                        .mapPlaceholder {
                            StockCellView.Placeholder(isWatchlisted: $0.isWatchlisted, toggleWatched: $0.toggleWatched, select: $0.select)
                        }
                    }
                    .mapConnectablePlaceholder {
                        StockCellView.Symbol(symbol: $0.symbol, name: $0.name)
                    }
                }
                return StockSearchView.Model(searchTerm: stockSearchViewControllerModel.searchTerm, symbols: mappedCellModels, search: stockSearchViewControllerModel.search)
            }
        }
    }
}

//
//  WatchlistViewSource.swift
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


// We can map the existing Source for the UIKit WatchlistViewController into the Source needed for the SwiftUI WatchlistView. This maintains the same single source of truth across both versions of the screen and means we don't need to change any underlying implementations of business logic, just convert the resulting models. Note that because "WatchlistViewControllerSource" holds all of its state in core dependencies like Cache and UserDefaults, we can instantiate a new copy of it here and it will still be fully in-sync with the UIKit instance of "WatchlistViewControllerSource" that is driving the UIKit screen implementation.
final class WatchlistViewSource: Source<WatchlistView.RenderedModel> {
    typealias Dependencies = WatchlistViewControllerSource.Dependencies
    init(dependencies: Dependencies) {
        super.init {
            WatchlistViewControllerSource(dependencies: dependencies).map { watchlistViewControllerModel in
                let convertedCellModels: [Source<WatchlistViewCell.RenderedModel>] = watchlistViewControllerModel.watchedStocks.map { watchedStockCellModel in
                    let sourcePlaceholder = watchedStockCellModel.model.placeholder
                    let mappedPlaceholder = WatchlistViewCell.Placeholder(symbol: sourcePlaceholder.symbol, name: sourcePlaceholder.name)
                    return connectable(placeholder: mappedPlaceholder) {
                        watchedStockCellModel.map { model in
                            model.asFetchable()
                                .map {
                                    WatchlistViewCell.Model(price: $0.price, percentChange: $0.percentChange, amountChange: $0.amountChange, trend: $0.trend == .up ? .up : .down, lastUpdatedDate: $0.lastUpdatedDate)
                                }
                        }
                    }
                }
                return WatchlistView.Model(watchedStocks: convertedCellModels, unwatch: watchlistViewControllerModel.unwatch.map { .init(symbol: $0.symbol, name: $0.name) }, select: watchlistViewControllerModel.select.map { .init(symbol: $0.symbol, name: $0.name) })
            }
        }
    }
}

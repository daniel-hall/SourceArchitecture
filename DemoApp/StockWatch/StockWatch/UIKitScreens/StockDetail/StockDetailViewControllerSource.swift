//
//  StockDetailViewControllerSource.swift
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

import UIKit
import SourceArchitecture


// A Source can compose / combine and transform other Sources to create the specific model Source needed by a particular screen.  This StockDetailViewControllerSource combines CompanyInfo, StockQuote data, company logo data, and Watchlist sources to create a Source of the StockDetailViewController's Model
class StockDetailViewControllerSource: Source<StockDetailViewController.RenderedModel> {
    typealias Dependencies = CompanyInfoSource.Dependencies & StockQuoteSource.Dependencies & WatchlistSource.Dependencies
    init(dependencies: Dependencies) {
        // If there is no selected symbol, return a fetched source .error case.  Otherwise, use the selected symbol to create a source that combines fetched values for CompanyInfo, StockQuote and Watchlist (for displaying and changing watched status)
        let detailSource: Source<StockDetailViewController.RenderedModel> = SelectedSymbolSource(dependencies: dependencies)
            .flatMap {
                switch $0 {
                case .notFound:
                    return .fromValue(.failure(.init(error: NSError(domain: "StockDetailSource", code: 1, userInfo: [NSLocalizedDescriptionKey: "No source has been selected"]), failedAttempts: 1, retry: .noOp)))
                case .found(let found):
                    let symbol = found.value
                    let companyInfo = CompanyInfoSource(dependencies: dependencies, symbol: found.value).retrying(.withExponentialBackoff, forwardErrorAfter: .never)
                    let stockQuote = StockQuoteSource(dependencies: dependencies, symbol: found.value).retrying(.withExponentialBackoff, forwardErrorAfter: .never)
                    let watched = WatchedSymbolSource(dependencies: dependencies, symbol: found.value)
                    return companyInfo
                        .combinedFetch(with: stockQuote)
                        .combined(with: watched)
                        .map { fetched, watched in
                            fetched.map { info, quote in
                                let logoSource = CompanyLogoImageSource(dependencies: dependencies, symbol: symbol)
                                    .mapFetchedValue(UIImage.init(data:))
                                    .map { $0.asFetchable() }
                                let isWatched = watched.found != nil
                                return StockDetailViewController.Model(symbol: info.symbol, companyName: info.name, companyDescription: info.description, ceoName: info.ceo, numberOfEmployees: info.numberOfEmployees, marketCap: quote.marketCap, logoSource: logoSource, isWatched: isWatched, toggleWatched: isWatched ? watched.found!.clear : watched.set.map { symbol })
                            }.asFetchable()
                        }
                }
            }
        super.init(detailSource)
    }
}

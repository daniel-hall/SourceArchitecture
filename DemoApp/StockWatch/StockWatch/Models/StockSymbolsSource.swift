//
//  StockSymbolsSource.swift
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


public struct StockSymbol: Hashable, Codable {
    let symbol: String
    let name: String
    let type: EquityType

    enum EquityType: String, Codable {
        case etf = "ETF"
        case stock = "Stock"
    }
}

final class StockSymbolsSource: Source<Fetchable<[StockSymbol]>> {
    typealias Dependencies = NetworkDependency & FileDependency
    init(dependencies: Dependencies) {
        let resource = StockSymbolsResource().addingIEXToken()
        // This is all it takes to download a network response, convert it to an app model, and persist it as a file, while broadcasting state updates to subscribers
        let persistedFetchedSource = dependencies.filePersistedNetworkResource(resource)
        super.init(persistedFetchedSource)
    }
}

private struct StockSymbolsResource: NetworkResource {
    typealias NetworkResponse = [NetworkSymbol]
    typealias Value = [StockSymbol]

    // This should be an exact match to the schema of the response
    struct NetworkSymbol: Decodable {
        let symbol: String
        let name: String
        let type: String?
    }
    let networkURLRequest = URLRequest(url: URL(string: "https://cloud.iexapis.com/stable/ref-data/symbols")!)
    // Here we can define a transformation between the network response and the model we want to use in the app
    func transform(networkResponse: [NetworkSymbol]) throws -> [StockSymbol] {
        networkResponse.filter { $0.type == "cs" }.map { .init(symbol: $0.symbol, name: $0.name, type: $0.type == "cs" ? .stock : .etf) }
    }
}

extension StockSymbolsResource: FileResource {
    // Redownload updated symbols every day
    var expireFileAfter: TimeInterval? { 60 * 60 * 24 }
    // By default File Resources are saved to the app's caches directory, so we only need to specify the path relative to that directory
    var filePath: String { "stockSymbols.json" }
}


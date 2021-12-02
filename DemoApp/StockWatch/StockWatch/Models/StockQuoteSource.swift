//
//  StockQuoteSource.swift
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


struct StockQuote: Codable {
    let timestamp: Date
    let open: String
    let close: String
    let price: String
    let changeAmount: String
    let changePercent: String
    let fiftyTwoWeekHigh: String
    let fiftyTwoWeekLow: String
    let peRatio: String
    let marketCap: String
}

final class StockQuoteSource: Source<FetchableWithPlaceholder<StockQuote, StockSymbol>> {
    typealias Dependencies = NetworkDependency & FileDependency
    init(dependencies: Dependencies, symbol: StockSymbol) {
        let resource = StockQuoteResource(symbol: symbol).addingIEXToken()
        let source = dependencies.filePersistedNetworkResource(resource).addingPlaceholder(symbol)
        super.init(source)
    }
}

// A Resource for a single file to hold all stock quotes
private struct AllStockQuotesResource: FileResource {
    typealias Value = [StockSymbol: StockQuote]
    let filePath = "stockQuotes.json"
}

// A Resource that describes how to retrieve, decode and transform a StockQuote from an endpoint
private struct StockQuoteResource: NetworkResource {
    typealias Value = StockQuote
    // This should be an exact match to the schema of the response
    struct NetworkResponse: Decodable {
        let symbol: String
        let companyName: String
        let open: Double?
        let close: Double?
        let high: Double?
        let low: Double?
        let latestPrice: Double?
        let marketCap: Int?
        let peRatio: Double?
        let week52High: Double?
        let week52Low: Double?
        let change: Double?
        let changePercent: Double?
    }
    var networkURLRequest: URLRequest {
        URLRequest(url: URL(string: "https://cloud.iexapis.com/stable/stock/\(symbol.symbol)/quote")!)
    }
    var networkRequestTimeout: TimeInterval? { 8 }
    let symbol: StockSymbol
    init(symbol: StockSymbol) {
        self.symbol = symbol
    }
    
    // Here we can define a transformation between the network response and the model we want to use in the app
    func transform(networkResponse: NetworkResponse) throws -> StockQuote {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let percentFormatter = NumberFormatter()
        percentFormatter.numberStyle = .percent
        percentFormatter.minimumIntegerDigits = 1
        percentFormatter.minimumFractionDigits = 2
        percentFormatter.maximumFractionDigits = 2
        func formatted(_ keyPath: KeyPath<NetworkResponse, Double?>) -> String {
            guard let value = networkResponse[keyPath: keyPath] else {
                return "$-.-"
            }
            let number = NSNumber(value: value)
            return formatter.string(from: number) ?? "$-.-"
        }
        return .init(timestamp: Date(), open: formatted(\.open), close: formatted(\.close), price: formatted(\.latestPrice), changeAmount: formatted(\.change), changePercent: networkResponse.changePercent.map{ percentFormatter.string(from: NSNumber(value: $0)) ?? "—%" } ?? "—%", fiftyTwoWeekHigh: formatted(\.week52High), fiftyTwoWeekLow: formatted(\.week52Low), peRatio: networkResponse.peRatio.map{ String($0) } ?? " — —", marketCap: networkResponse.marketCap.map{ formatter.string(from: NSNumber(value: $0)) ?? "—" } ?? "—")
    }
    
    func decode(data: Data, response: URLResponse) throws -> NetworkResponse {
        try JSONDecoder().decode(NetworkResponse.self, from: data)
    }
}

// Define how to insert / retrieve a single stock quote from the entire file of all stock quotes
extension StockQuoteResource: ResourceElement {
    var parentResource: AllStockQuotesResource { .init() }
    func set(element: StockQuote?) -> ([StockSymbol : StockQuote]?) throws -> [StockSymbol : StockQuote] {
        if let quote = element {
            return {
                var quotes = $0 ?? [:]
                quotes[symbol] = quote
                return quotes
            }
        } else {
            return {
                var quotes = $0 ?? [:]
                quotes.removeValue(forKey: symbol)
                return quotes
            }
        }
    }
    var elementIdentifier: String { "StockQuote-\(symbol.symbol)" }
    func getElement(from value: [StockSymbol : StockQuote]) throws -> StockQuote? {
        value[symbol]
    }
}

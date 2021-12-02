//
//  CompanyLogoSource.swift
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


/// Source for retrieving the image data for a Company's logo
final class CompanyLogoImageSource: Source<FetchableWithPlaceholder<Data, StockSymbol>> {
    typealias Dependencies = NetworkDependency & FileDependency
    init(dependencies: Dependencies, symbol: StockSymbol) {
        let urlSource = CompanyLogoURLSource(dependencies: dependencies, symbol: symbol)
            .addingPlaceholder(symbol)
        super.init {
            urlSource.flatMap {
                switch $0 {
                case .fetched(let fetched): return dependencies.filePersistedNetworkResource(ImageDataResource(url: fetched.value)).addingPlaceholder(symbol)
                default: return .fromValue($0.map { _ in Data() })
                }
            }
        }
    }
}

/// Source for retrieving the URL for a Company's logo
private final class CompanyLogoURLSource: Source<FetchableWithPlaceholder<URL, StockSymbol>> {
    typealias Dependencies = NetworkDependency & FileDependency
    init(dependencies: Dependencies, symbol: StockSymbol) {
        let resource = CompanyLogoURLResource(symbol: symbol).addingIEXToken()
        let source = dependencies.filePersistedNetworkResource(resource).addingPlaceholder(symbol)
        super.init(source)
    }
}

private struct CompanyLogoURLResource: NetworkResource, CacheResource, FileResource {
    struct NetworkResponse: Decodable {
        let url: String?
    }
    var networkURLRequest: URLRequest {
        URLRequest(url: URL(string: "https://cloud.iexapis.com/stable/stock/\(symbol.symbol)/logo")!)
    }
    var filePath: String { "logoURLs/\(symbol.symbol)" }
    let symbol: StockSymbol
    var cacheIdentifier: String { "logo—url-\(symbol.symbol)" }
    
    func transform(networkResponse: NetworkResponse) throws -> URL {
        guard let url = URL(string: networkResponse.url ?? "") else {
            throw NSError(domain: "No valid URL received", code: 0, userInfo: nil)
        }
        return url
    }
}

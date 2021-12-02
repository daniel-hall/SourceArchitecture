//
//  CompanyInfoSource.swift
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


struct CompanyInfo: Codable {
    let symbol: String
    let name: String
    let industry: String
    let website: String
    let description: String
    let ceo: String
    let numberOfEmployees: String
}

final class CompanyInfoSource: Source<FetchableWithPlaceholder<CompanyInfo, StockSymbol>> {
    typealias Dependencies = NetworkDependency & CacheDependency & FileDependency
    init(dependencies: Dependencies, symbol: StockSymbol) {
        let resource = CompanyInfoResource(symbol: symbol).addingIEXToken()
        let source = dependencies.filePersistedNetworkResource(resource).addingPlaceholder(symbol)
        super.init(source)
    }
}

// A Resource describing how to retrieve CompanyInfo from an endpoint
private struct CompanyInfoResource: NetworkResource {
    typealias Value = CompanyInfo
    typealias Placeholder = StockSymbol
    // This should be an exact match to the schema of the response
    struct NetworkResponse: Decodable {
        let symbol: String
        let companyName: String
        let industry: String?
        let website: String?
        let description: String?
        let CEO: String?
        let employees: Int?
    }

    var networkURLRequest: URLRequest {
        URLRequest(url: URL(string: "https://cloud.iexapis.com/stable/stock/\(symbol.symbol)/company")!)
    }

    // Here we can define a transformation between the network response and the model we want to use in the app
    func transform(networkResponse: NetworkResponse) throws -> CompanyInfo {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return .init(symbol: networkResponse.symbol, name: networkResponse.companyName, industry: networkResponse.industry.orNotAvailable, website: networkResponse.website.orNotAvailable, description: networkResponse.description.orNotAvailable, ceo: networkResponse.CEO.orNotAvailable, numberOfEmployees: networkResponse.employees.flatMap(numberFormatter.string).orNotAvailable)
    }

    let symbol: StockSymbol
}

extension CompanyInfoResource: FileResource {
    var filePath: String { "companyInfo/\(symbol).json" }
    var expireFileAfter: TimeInterval? { 24 * 60 * 60 }
}

private extension Optional where Wrapped == String {
    var orNotAvailable: String {
        self?.isEmpty == false ? self! : "N/A"
    }
}

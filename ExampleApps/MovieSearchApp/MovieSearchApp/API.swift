//
//  API.swift
//  MovieSearchApp
//  SourceArchitecture
//
//  Copyright (c) 2022 Daniel Hall
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


/// A type that defines all the different API calls and responses that can be made by the MovieSearch app
enum API {

    static func movieSearch(for searchTerm: String, page: Int?) -> AnySource<Fetchable<MovieSearchResponse>> {
        let urlRequest = URLRequest(url: .init(string: "https://api.themoviedb.org/3/search/movie?api_key=e599956308c0060d33c166d0e5914c16&language=en-US&query=\(searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm)&page=\(page ?? 1)")!)
        return FetchableDataSource(urlRequest: urlRequest).eraseToAnySource().jsonDecoded()
    }

    static func movieDetails(for movieID: Int) -> AnySource<Fetchable<MovieDetailsResponse>> {
        let urlRequest = URLRequest(url: .init(string: "https://api.themoviedb.org/3/movie/\(movieID)?api_key=e599956308c0060d33c166d0e5914c16&language=en-US")!)
        return FetchableDataSource(urlRequest: urlRequest).eraseToAnySource().jsonDecoded()
    }

    static func movieCredits(for movieID: Int) -> AnySource<Fetchable<MovieCreditsResponse>> {
        let urlRequest = URLRequest(url: .init(string: "https://api.themoviedb.org/3/movie/\(movieID)/credits?api_key=e599956308c0060d33c166d0e5914c16&language=en-US")!)
        return FetchableDataSource(urlRequest: urlRequest).eraseToAnySource().jsonDecoded()
    }

    static func image(from url: URL) -> AnySource<Fetchable<UIImage>> {
        let urlRequest = URLRequest(url: url)
        return FetchableDataSource(urlRequest: urlRequest).eraseToAnySource().decoded {
            guard let image = UIImage(data: $0) else {
                throw NSError(domain: #file + #function, code: 0, userInfo: [NSLocalizedDescriptionKey: "Could decode UIImage from data"])
            }
            return image
        }
    }
}

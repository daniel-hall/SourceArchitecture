//
//  AppDependencies.swift
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

import Foundation
import SourceArchitecture
import UIKit


/// A struct that holds all the dependencies used within the app. It conforms to all the protocols required by the app's Sources and Views. In test scenarios, various MockDependencies structs that conforms to the protocols can be used instead or deserialized from a configuration JSON!
fileprivate struct AppDependencies: LazyStoring, MainView.Dependencies & MovieSearchSource.Dependencies & MovieDetailsSource.Dependencies {

    fileprivate let _storage = LazyStorage()
    private let cache = CachePersistence(.withMaxSize(78600000)) // Set a max cache size of 75MB

    let selectedMovie = SelectedMovieSource().eraseToAnySource()

    private func image(from url: URL) -> AnySource<Fetchable<UIImage>> {
        API.image(from: url)
    }

    func movieThumbnail(from url: URL) -> AnySource<Fetchable<UIImage>> {
        let descriptor = CacheDescriptor(key: url.absoluteString)
        return image(from: url).persisted(using: cache.persistableSource(for: descriptor))
    }

    func moviePoster(from url: URL) -> AnySource<Fetchable<UIImage>> {
        let descriptor = CacheDescriptor(key: url.absoluteString)
        return image(from: url).persisted(using: cache.persistableSource(for: descriptor))
    }

    func movieSearchResponse(for searchTerm: String, page: Int?) -> AnySource<Fetchable<MovieSearchResponse>> {
        API.movieSearch(for: searchTerm, page: page)
    }

    func movieDetails(for movieID: Int) -> AnySource<Fetchable<MovieDetailsResponse>> {
        return API.movieDetails(for: movieID )
    }

    func movieCredits(for movieID: Int) -> AnySource<Fetchable<MovieCreditsResponse>> {
        return API.movieCredits(for: movieID)
    }

    var movieSearchSource: AnySource<Fetchable<MovieSearch>> {
        lazy { MovieSearchSource(dependencies: self).eraseToAnySource() }
    }

    var movieDetailsSource: AnySource<Fetchable<MovieDetails>> {
         MovieDetailsSource(dependencies: self).eraseToAnySource()
    }
}

let appDependencies: MainView.Dependencies & MovieSearchSource.Dependencies & MovieDetailsSource.Dependencies = AppDependencies()


extension UIViewController {
    @IBSegueAction private func showMovieSearch(_ coder: NSCoder) -> MovieSearchViewController? {
        .init(source: appDependencies.movieSearchSource, coder: coder)
    }
}

extension UIViewController {
    @IBSegueAction private func showMovieDetails(_ coder: NSCoder) -> MovieDetailsViewController? {
        .init(source: appDependencies.movieDetailsSource, coder: coder)
    }
}

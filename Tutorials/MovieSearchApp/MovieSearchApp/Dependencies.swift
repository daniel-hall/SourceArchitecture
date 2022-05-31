//
//  Dependencies.swift
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
struct AppDependencies: MainView.Dependencies & MovieSearchSource.Dependencies & MovieDetailsSource.Dependencies {
    let cache = CachePersistence(.withMaxSize(10000000))
    let selectedMovie: Source<SelectedMovie> = SelectedMovieSource().eraseToSource()

    private func image(from url: URL) -> Source<Fetchable<UIImage>> {
        API.image(from: url)
    }

    func movieThumbnail(from url: URL) -> Source<Fetchable<UIImage>> {
        let descriptor = CacheDescriptor(key: url.absoluteString)
        return image(from: url).persisted(using: cache.persistableSource(for: descriptor))
    }

    func moviePoster(from url: URL) -> Source<Fetchable<UIImage>> {
        let descriptor = CacheDescriptor(key: url.absoluteString)
        return image(from: url).persisted(using: cache.persistableSource(for: descriptor))
    }

    func movieSearchResponse(for searchTerm: String, page: Int?) -> Source<Fetchable<MovieSearchResponse>> {
        API.movieSearch(for: searchTerm, page: page)
    }

    func movieDetails(for movieID: Int) -> Source<Fetchable<MovieDetailsResponse>> {
        return API.movieDetails(for: movieID )
    }

    func movieCredits(for movieID: Int) -> Source<Fetchable<MovieCreditsResponse>> {
        return API.movieCredits(for: movieID)
    }

    var movieSearchViewModelState: ModelState<MovieSearchView.Model> {
        MovieSearchSource(dependencies: self).eraseToSource().$model
    }

    var movieDetailsViewModelState: ModelState<MovieDetailsView.Model> {
        ConnectableSource { MovieDetailsSource(dependencies: self).eraseToSource() }.eraseToSource().$model
    }
}

let appDependencies = AppDependencies()

//
//  MovieSearch.swift
//  MovieSearchApp
//  SourceArchitecture
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

/// A model that describes the results of a movie search, including the current search term, plus actions to loadMore and search for a new term
struct MovieSearch {
    let currentSearchTerm: String?
    let results: [Result]
    let search: Action<String?>
    let loadMore: Action<Void>?

    struct Result: Identifiable {
        let id: Int
        let title: String
        let description: String
        let releaseDate: String
        let rating: String
        // A Source that will fetch a thumbnail image for the movie and has a placeholder image
        let thumbnail: Source<FetchableWithPlaceholder<UIImage?, UIImage>>
        let select: Action<Void>
    }
}

// This Source makes network requests to get search results, converts the network response models to the expected app model, and keeps track of current page and total pages of result to manage loading more when requested
final class MovieSearchSource: Source<Fetchable<MovieSearch>>, ActionSource {
    typealias Dependencies = NetworkDependency & CacheDependency

    // Here we define what Actions this Source can create, and what methods they map to on this Source
    struct Actions: ActionMethods {
        var search = ActionMethod(MovieSearchSource.search)
        var loadMore = ActionMethod(MovieSearchSource.loadMore)
    }

    // Any var / mutable property a Source uses should be placed in a MutableProperties struct so it can be managed by the Source's MutableState. A Source's MutableState automatically manages locking and thread safety under the hood.
    struct MutableProperties {
        // The Source that will update with the actual network request results. A new one is created for every new API query
        fileprivate var fetchableSource: Source<Fetchable<MovieSearchResource.Value>>?
        fileprivate var searchTerm: String?
        fileprivate var accumulatedResults = [MovieSearch.Result]()
        fileprivate var currentPage = 1
        fileprivate var totalPages = 1
    }
    // If we have MutableProperties, we should declare MutableState<MutableProperties> for our state instead of just normal State
    let state: MutableState<MutableProperties>
    // We can compose the behavior / functionality of the currently selected movie source
    let selectedMovieSource: SelectedMovieSource
    let dependencies: Dependencies
    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.selectedMovieSource = SelectedMovieSource(dependencies: dependencies)
        state = .init(mutableProperties: .init()) { state in .fetched(.init(value: .init(currentSearchTerm: nil, results: [], search: state.search, loadMore: state.loadMore), refresh: .noOp)) }
        super.init(state)
    }

    private func handleResult() {
        guard let source = state.fetchableSource else { return }
        // Here we map / transform the results of te API request into the app-specific MovieSearch model and its properties
        let movieSearch: Fetchable<MovieSearch> = source.model.map {
            // Here we are mapping the individual results to the app-specific MovieSearch.Result model
            let results: [MovieSearch.Result] = $0.results.compactMap {
                guard let id = $0.id, let title = $0.title, let overview = $0.overview, let releaseDate = $0.release_date else { return nil }
                let thumbnailURL = $0.poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w92\($0)") }
                let thumbnailSource = thumbnailURL.map { [dependencies = dependencies] url in
                    // The deferred wrapper around the network Source ensures that the request is not made / initiated until something actually subscribes to the Source or asks for its current value. This way, we aren't immediately fetching hundreds of thumbnails!
                    deferred {
                        // Automatically caching network resources is this easy
                        dependencies.cachedNetworkResource(MovieImageResource(url: url))
                        .addingPlaceholder(UIImage(systemName: "photo")!)
                    }
                } ?? .fromValue(.fetching(.init(placeholder: UIImage(systemName: "photo")!, progress: nil)))

                return MovieSearch.Result(id: id, title: title, description: overview, releaseDate: releaseDate, rating: "⭐️ " + String(format:"%.01f", $0.vote_average ?? 0), thumbnail: thumbnailSource, select: selectedMovieSource.model.setSelection.map { id })
            }
            // Add to our existing results
            state.accumulatedResults += results
            state.currentPage = $0.page ?? 1
            state.totalPages = $0.total_pages ?? 1

            return MovieSearch(currentSearchTerm: state.searchTerm, results: state.accumulatedResults, search: state.search, loadMore: state.currentPage < state.totalPages ? state.loadMore : nil)
        }
        // If we are loading additional results, don't set a ".fetching" state, only add new results once they are fetched
        if !state.accumulatedResults.isEmpty {
            guard case .fetched = movieSearch else { return }
        }
        state.setModel(movieSearch)
    }

    private func search(term: String?) {
        let term = term?.isEmpty == true ? nil : term
        if term == state.searchTerm { return }
        state.searchTerm = term
        // If we changed out search term, then we need to clear our existing results
        state.accumulatedResults = []
        guard let term = term else {
            state.setModel(.fetched(.init(value: .init(currentSearchTerm: term, results: [], search: state.search, loadMore: state.loadMore), refresh: .noOp)))
            return
        }
        state.fetchableSource = dependencies.networkResource(MovieSearchResource(searchTerm: term, page: nil))
        state.fetchableSource?.subscribe(self, method: MovieSearchSource.handleResult)
    }

    private func loadMore() {
        guard let searchTerm = state.searchTerm, !searchTerm.isEmpty, state.currentPage < state.totalPages else {
            return
        }
        // Make a request for the next page of results for the current search term
        state.fetchableSource = dependencies.networkResource(MovieSearchResource(searchTerm: searchTerm, page: state.currentPage + 1))
        state.fetchableSource?.subscribe(self, method: MovieSearchSource.handleResult)
    }
}

/// Retrieve a UIImage from the provided URL and give it an identifier for caching
struct MovieImageResource: NetworkResource, CacheResource {
    typealias Value = UIImage?
    var cacheIdentifier: String { url.absoluteString }
    var networkURLRequest: URLRequest { .init(url: url) }
    let url: URL
    func decode(data: Data, response: URLResponse) throws -> UIImage? {
        UIImage(data: data)
    }
}

/// Retrieve Movie Search Results by passing in a search term and a results page
private struct MovieSearchResource: NetworkResource {
    struct NetworkResponse: Decodable {
        let page: Int?
        let total_pages: Int?
        let total_results: Int?
        let results: [Result]

        struct Result: Decodable {
            let id: Int?
            let title: String?
            let overview: String?
            let release_date: String?
            let poster_path: String?
            let vote_average: Float?
        }
    }
    let searchTerm: String
    let page: Int?
    var networkURLRequest: URLRequest {
        .init(url: .init(string: "https://api.themoviedb.org/3/search/movie?api_key=e599956308c0060d33c166d0e5914c16&language=en-US&query=\(searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm)&page=\(page ?? 1)")!)
    }
}

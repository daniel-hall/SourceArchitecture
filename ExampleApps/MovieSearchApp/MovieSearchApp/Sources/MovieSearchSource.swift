//
//  MovieSearchSource.swift
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


// MARK: - Models -

/// A Domain model that describes the results of a movie search, including the current search term, plus actions to loadMore and search for a new term
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
        let thumbnail: Source<FetchableWithPlaceholder<UIImage, UIImage>>
        let select: Action<Void>
    }
}

/// A Decodable model that is expected from the MovieSearch API Endpoint
struct MovieSearchResponse: Decodable {
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


// MARK: - Dependencies -

protocol FetchableMovieSearchResponseDependency {
    func movieSearchResponse(for searchTerm: String, page: Int?) -> Source<Fetchable<MovieSearchResponse>>
}

protocol FetchableMovieThumbnailDependency {
    func movieThumbnail(from url: URL) -> Source<Fetchable<UIImage>>
}

// This Source makes network requests to get search results, converts the network response models to the expected app model, and keeps track of current page and total pages of result to manage loading more when requested
final class MovieSearchSource: SourceOf<Fetchable<MovieSearch>> {

    typealias Dependencies = FetchableMovieSearchResponseDependency & FetchableMovieThumbnailDependency & SelectedMovieDependency

    @Action(search) private var searchAction
    @Action(loadMore) private var loadMoreAction
    @Action(refresh) private var refreshAction


    // The Source that will update with the actual network request results. A new one is created for every new API query
    @Threadsafe private var fetchableSource: Source<Fetchable<MovieSearchResponse>>?
    @Threadsafe private var searchTerm: String?
    @Threadsafe private var accumulatedResults = [MovieSearch.Result]()
    @Threadsafe private var currentPage = 1
    @Threadsafe private var totalPages = 1

    /// The default initial value of the Model that this Source should return if no other model has been calculated or set yet
    lazy var initialModel = Fetchable<MovieSearch>.fetched(.init(value: .init(currentSearchTerm: nil, results: [], search: searchAction, loadMore: loadMoreAction), refresh: refreshAction))

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    private func handleResponse(_ response: Fetchable<MovieSearchResponse>) {
        let movieSearch: Fetchable<MovieSearch> = response.map {
            let results: [MovieSearch.Result] = $0.results.compactMap {
                // Make sure we have all the necessary values in our API response
                guard let id = $0.id, let title = $0.title, let overview = $0.overview, let releaseDate = $0.release_date else {
                    return nil
                }
                // If there is a poster for the movie, create a URL for the thumbnail
                let thumbnailURL = $0.poster_path.flatMap {
                    URL(string: "https://image.tmdb.org/t/p/w92\($0)")
                }
                // Create a Source to fetched the thumbnail image. If there is no URL then return a .failure with a placeholder image
                let thumbnailSource = thumbnailURL.map {
                    dependencies.movieThumbnail(from: $0).addingPlaceholder(UIImage(systemName: "photo")!)
                } ?? Source(model: .failure(.init(placeholder: UIImage(systemName: "photo")!, error: NSError(domain: #file + #function, code: 0, userInfo: [NSLocalizedDescriptionKey: "No thumbnail URL"]), failedAttempts: 1, retry: nil)))
                
                // Create a selection Action for this result by mapping the selected movie setSelection Action<Int?> to Action<Void>, providing the current ID as the input
                let selectAction = dependencies.selectedMovie.model.set.map { id }

                // Return our domain's MovieSearch.Result model
                return .init(id: id, title: title, description: overview, releaseDate: releaseDate, rating: "⭐️ " + String(format:"%.01f", $0.vote_average ?? 0), thumbnail: thumbnailSource, select: selectAction)
            }
            // Add to our existing results (we have to manually filter because the API returns duplicates!)
            accumulatedResults += results.filter { result in !accumulatedResults.contains{ $0.id == result.id } }
            currentPage = $0.page ?? 1
            totalPages = $0.total_pages ?? 1

            return MovieSearch(currentSearchTerm: searchTerm, results: accumulatedResults, search: searchAction, loadMore: currentPage < totalPages ? loadMoreAction : nil)
        }
        // If we are loading additional results, don't set a ".fetching" state, only add new results once they are fetched
        if case .fetching = response, !accumulatedResults.isEmpty {
            return
        }
        model = movieSearch
    }

    private func search(term: String?) {
        // If the search term is an empty string, just consider it nil
        let term = term?.isEmpty == true ? nil : term
        // If the term is our existing search term, then return without doing a new search
        if term == searchTerm { return }
        searchTerm = term
        // If we changed out search term, then we need to clear our existing results
        accumulatedResults = []
        guard let term = term else {
            // If our term is nil, then just show empty results
            model = .fetched(Fetchable.Fetched(value: MovieSearch(currentSearchTerm: term, results: [], search: searchAction, loadMore: loadMoreAction), refresh: refreshAction))
            return
        }
        // Fetch the search response from the API
        fetchableSource = dependencies.movieSearchResponse(for: term, page: nil)
        fetchableSource?.subscribe(self, method: MovieSearchSource.handleResponse)
    }

    private func refresh() {
        fetchableSource?.model.fetched?.refresh?()
    }

    private func loadMore() {
        guard let searchTerm = searchTerm, !searchTerm.isEmpty, currentPage < totalPages else {
            return
        }
        // Make a request for the next page of results for the current search term
        fetchableSource = dependencies.movieSearchResponse(for: searchTerm, page: currentPage + 1)
        fetchableSource?.subscribe(self, method: MovieSearchSource.handleResponse)
    }
}

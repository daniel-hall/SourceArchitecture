//
//  MovieDetails.swift
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

/// App-specfic model that contains the various details we want to show about a movie, pulled from multiple endpoints
struct MovieDetails {
    let id: Int
    let title: String
    let tagline: String?
    let posterSource: Source<FetchableWithPlaceholder<UIImage?, UIImage>>
    let description: String
    let releaseDate: String
    let budget: String
    let boxOffice: String
    let director: String
    let topCast: [String]
    let rating: String
}

/// This Source fetches data from two different APIs and transforms the results into a single app-specific model
final class MovieDetailsSource: Source<Fetchable<MovieDetails>> {
    typealias Dependencies = NetworkDependency & CacheDependency
    init(dependencies: Dependencies) {
        // We flatMap from SelectedMovieSource, so every time the currently selected movie changes in the app, it triggers a new request to the two endpoints to get information for the currently selected movie
        let combinedFetchedSource = SelectedMovieSource(dependencies: dependencies).flatMap {
            // combinedFetch will managed the fetching, failure, and fetched state from two different Sources and merge them into a single fetching, failure or fetched state that is a tuple of the Values from the original sources
            dependencies.networkResource(MovieDetailsResource(movieID: $0.selectedID)).combinedFetch(with: dependencies.networkResource(MovieCreditsResource(movieID: $0.selectedID)))
        }
        // Now that we have a fetched source of values from both APIs, we map those responses into the final model type we need
        let mappedSource: Source<Fetchable<MovieDetails>> = combinedFetchedSource.mapFetchedValue { details, credits in
            let posterURL = details.poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/original\($0)") }
            let posterSource = posterURL.map { url in
                deferred {
                    dependencies.cachedNetworkResource(MovieImageResource(url: url))
                        .addingPlaceholder(UIImage(systemName: "photo")!)
                }
            } ?? .fromValue(.fetching(.init(placeholder: UIImage(systemName: "photo")!, progress: nil)))
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency

            return MovieDetails(id: details.id ?? 0, title: details.title ?? "N/A", tagline: details.tagline, posterSource: posterSource, description: details.overview ?? "", releaseDate: details.release_date ?? "N/A", budget: details.budget.flatMap { formatter.string(from: .init(value: $0)) } ?? "N/A" , boxOffice: details.revenue.flatMap { formatter.string(from: .init(value: $0)) } ?? "N/A", director: credits.crew.first { $0.job?.lowercased() == "director" }?.name ?? "N/A", topCast: credits.cast.prefix(4).compactMap { $0.name }, rating: "⭐️ " + String(format:"%.01f", details.vote_average ?? 0))
        }
        super.init(mappedSource)
    }
}

/// Retrieves details for the specific movie ID from the TMDB GetDetails API
private struct MovieDetailsResource: NetworkResource {
    struct NetworkResponse: Decodable {
        let id: Int?
        let title: String?
        let tagline: String?
        let overview: String?
        let budget: Int?
        let poster_path: String?
        let revenue: Int?
        let release_date: String?
        let vote_average: Float?
    }
    var networkURLRequest: URLRequest {
        .init(url: .init(string: "https://api.themoviedb.org/3/movie/\(movieID)?api_key=e599956308c0060d33c166d0e5914c16&language=en-US")!)
    }
    let movieID: Int
}

/// Retrieves credits for the specific movie ID from the TMDB Credits API
private struct MovieCreditsResource: NetworkResource {
    struct CastMember: Decodable {
        let name: String?
        let character: String?
    }
    struct CrewMember: Decodable {
        let name: String?
        let job: String?
    }
    struct NetworkResponse: Decodable {
        let cast: [CastMember]
        let crew: [CrewMember]
    }
    var networkURLRequest: URLRequest {
        .init(url: .init(string: "https://api.themoviedb.org/3/movie/\(movieID)/credits?api_key=e599956308c0060d33c166d0e5914c16&language=en-US")!)
    }
    let movieID: Int
}

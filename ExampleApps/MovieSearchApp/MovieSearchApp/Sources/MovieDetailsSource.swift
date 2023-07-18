//
//  MovieDetailsSource.swift
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

/// Domain-specfic model that contains the various details we want to show about a movie, pulled from multiple endpoints
struct MovieDetails {
    let id: Int
    let title: String
    let tagline: String?
    let poster: AnySource<FetchableWithPlaceholder<UIImage, UIImage>>
    let description: String
    let releaseDate: String
    let budget: String
    let boxOffice: String
    let director: String
    let topCast: [String]
    let rating: String
}

/// Decodable model that is expected from the MovieDetails endpoint
struct MovieDetailsResponse: Decodable {
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

/// Decodable CastMember
struct CastMemberResponse: Decodable {
    let name: String?
    let character: String?
}

/// Decodable CrewMember
struct CrewMemberResponse: Decodable {
    let name: String?
    let job: String?
}

/// Decodable model that is expected from the MovieCredits endpoint
struct MovieCreditsResponse: Decodable {
    let cast: [CastMemberResponse]
    let crew: [CrewMemberResponse]
}


// MARK: - Dependencies -

protocol FetchableMovieDetailsDependency {
    func movieDetails(for movieID: Int) -> AnySource<Fetchable<MovieDetailsResponse>>
}

protocol FetchableMovieCreditsDepedency {
    func movieCredits(for movieID: Int) -> AnySource<Fetchable<MovieCreditsResponse>>
}

protocol FetchableMoviePosterDependency {
    func moviePoster(from url: URL) -> AnySource<Fetchable<UIImage>>
}

/// This Source fetches data from two different APIs and transforms the results into a single app-specific model. Since it only applies operators to other Sources and manages no model or state of its own, it is a "ComposedSource"
final class MovieDetailsSource: ComposedSource<Fetchable<MovieDetails>> {
    typealias Dependencies = FetchableMoviePosterDependency & SelectedMovieDependency & FetchableMovieDetailsDependency & FetchableMovieCreditsDepedency

    init(dependencies: Dependencies) {
        super.init {
            // We flatMap from the selectedMovie, so every time the currently selected movie changes in the app, it triggers a new request to the two endpoints to get information for the currently selected movie
            let combinedFetchedSource: AnySource<Fetchable<(MovieDetailsResponse, MovieCreditsResponse)>> = dependencies.selectedMovie.flatMap { [dependencies] in
                // combinedFetch will managed the fetching, failure, and fetched state from two different Sources and merge them into a single fetching, failure or fetched state that is a tuple of the Values from the original sources
                guard let id = $0.value else {
                    return SingleValueSource( Fetchable<MovieDetailsResponse>.fetching(.init(progress: nil))).eraseToAnySource().combinedFetch(with: SingleValueSource( Fetchable<MovieCreditsResponse>.fetching(.init(progress: nil))).eraseToAnySource())
                }
                return dependencies.movieDetails(for: id).combinedFetch(with: dependencies.movieCredits(for: id))
            }
            // Now that we have a fetched source of values from both APIs, we map those responses into the final model type we need
            return combinedFetchedSource.mapFetchedValue { [dependencies] details, credits in
                // If a poster path exists, create a URL to the full size image
                let posterURL = details.poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
                // Create a Source for the fetched poster image. If there isn't a URL, return a failure with a placeholder image
                let posterSource: AnySource<FetchableWithPlaceholder<UIImage, UIImage>> = posterURL.map { url in
                    dependencies.moviePoster(from: url).addingPlaceholder(UIImage(systemName: "photo")!)
                } ?? SingleValueSource(.failure(.init(placeholder: UIImage(systemName: "photo")!, error: NSError(domain: #file + #function, code: 0, userInfo: [NSLocalizedDescriptionKey: "No poster URL"]), failedAttempts: 1, retry: nil))).eraseToAnySource()
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency

                return MovieDetails(id: details.id ?? 0, title: details.title ?? "N/A", tagline: details.tagline, poster: posterSource, description: details.overview ?? "", releaseDate: details.release_date ?? "N/A", budget: details.budget.flatMap { formatter.string(from: .init(value: $0)) } ?? "N/A" , boxOffice: details.revenue.flatMap { formatter.string(from: .init(value: $0)) } ?? "N/A", director: credits.crew.first { $0.job?.lowercased() == "director" }?.name ?? "N/A", topCast: credits.cast.prefix(4).compactMap { $0.name }, rating: "⭐️ " + String(format:"%.01f", details.vote_average ?? 0))
            }
        }
    }
}

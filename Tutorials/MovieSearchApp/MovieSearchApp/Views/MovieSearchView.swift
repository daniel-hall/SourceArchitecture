//
//  MovieSearchView.swift
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

import SwiftUI
import SourceArchitecture

// We declare a protocol for the MovieSearchView's Source Dependency. Having a protocol like this allows us to create a top-level container that holds all dependencies for the view hierarchy (and making them mockable / injectable) while being compiler checked
protocol MovieSearchViewDependency {
    var movieSearchViewSource: Source<MovieSearchView.RenderedModel> { get }
}

// Source Architecture Renderers must declare a Source that they use. The AnySource / Source type implement ObservableObject and when its value changes, the View will automatically recalculate its body based on the new model value.
struct MovieSearchView: View, Renderer {
    // This view dependencies on its own Source dependency, plus the Dependencies of any children is must create
    typealias Dependencies = MovieSearchViewDependency & MovieDetailsView.Dependencies
    @ObservedObject var source: AnySource<Fetchable<MovieSearch>>
    @State var searchText = ""
    private let dependencies: Dependencies
    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        let source = dependencies.movieSearchViewSource
        self.source = source
    }
    var body: some View {
        VStack {
            switch model {
            case .fetching:
                ProgressView()
            case .failure(let failure):
                Text(failure.error.localizedDescription)
                failure.retry.map { retry in Button("Retry", action: { try? retry() }) }
            case .fetched(let fetched):
                IsSearchingResponder { if !$0 { try? fetched.search(nil) } }
                if fetched.results.isEmpty {
                    Text("No Results").foregroundColor(.gray)
                } else {
                    List(fetched.results) { result in
                        HStack(spacing: 0) {
                            MovieSearchResultView(result: result).onAppear {
                                // If this result is the tenth from the last result currently loaded, try to load more
                                if result.id == fetched.results.suffix(10).first?.id {
                                    try? fetched.loadMore?()
                                }
                            }
                            NavigationLink("") {
                                MovieDetailsView(dependencies: dependencies)
                                    .navigationTitle(result.title)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .onAppear {
                                        // When the MovieDetailView is show, we want to make sure to select the the result that was tapped so the MovieDetails are populated for that result
                                        try? result.select()
                                    }
                            }.fixedSize()
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .navigationTitle("Movies")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onSubmit(of: .search) {
            try? model.fetched?.search(searchText)
        }
    }
}

// SwiftUI only tells a child view of the view that implements .searchable when the .isSearching environment value changes. So we create a small empty child view that will run a closure for use when it detects a change in this environment value
struct IsSearchingResponder: View {
    @Environment(\.isSearching) var isSearching
    let onChangeOfIsSearching: (Bool) -> Void
    var body: some View {
        EmptyView()
            .onChange(of: isSearching) { onChangeOfIsSearching($0) }
    }
}

struct MovieSearchResultView: View, Renderer {
    @ObservedObject var source: AnySource<FetchableWithPlaceholder<UIImage?, UIImage>>
    let result: MovieSearch.Result
    init(result: MovieSearch.Result) {
        self.result = result
        source = result.thumbnail
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(uiImage: model.fetched?.value ?? model.placeholder)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title).font(.headline).allowsTightening(true)
                HStack(spacing: 8) {
                    Text(result.rating)
                    Spacer()
                    Text(result.releaseDate)
                }
                Text(result.description).font(.caption).lineLimit(3)
            }
        }
    }
}

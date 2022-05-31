//
//  MovieDetailView.swift
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

import SourceArchitecture
import SwiftUI


// We declare a protocol for the MovieDetailView's Source Dependency. Having a protocol like this allows us to create a top-level container that holds all dependencies for the view hierarchy (and makes them mockable / injectable) while being compiler checked
protocol MovieDetailsViewModelStateDependency {
    var movieDetailsViewModelState: ModelState<MovieDetailsView.Model> { get }
}

// Source Architecture Views / Renderers must declare a source property to hold a Source of the Model that they use. The Source type implements ObservableObject and when its value changes, the View will automatically recalculate its body based on the new model value.
struct MovieDetailsView: View, Renderer {
    typealias Dependencies = MovieDetailsViewModelStateDependency
    @ModelState var model: Connectable<Fetchable<MovieDetails>>
    init(dependencies: Dependencies) {
        _model = dependencies.movieDetailsViewModelState
    }
    var body: some View {
        Group {
            switch model.connected?.value {
            case .none:
                ProgressView().onAppear { model.connect() }
            case .fetching:
                ProgressView()
            case .failure(let failure):
                Text(failure.error.localizedDescription)
                failure.retry.map { retry in Button("Retry") { retry() } }
            case .fetched(let fetched):
                ScrollView {
                    VStack(alignment: .center, spacing: 12) {
                        PosterView(modelState: fetched.poster).aspectRatio(contentMode: .fit).frame(width: 200, height: 300)
                        VStack(spacing: 5) {
                            Text(fetched.title).font(.title2)
                            if let tagline = fetched.tagline {
                                Text(tagline).font(.subheadline)
                            }
                            HStack(spacing: 12) {
                                Text(fetched.rating)
                                Text("|")
                                HStack {
                                    Text("Released:").font(.caption).fontWeight(.bold)
                                    Text(fetched.releaseDate).font(.caption)
                                }
                            }
                        }
                        VStack(spacing: 12) {
                            HStack(alignment: .top) {
                                VStack (alignment: .leading) {
                                    Text("Director:")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(fetched.director)
                                }
                                VStack (alignment: .leading) {
                                    Text("Top Cast:")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(fetched.topCast.joined(separator: ", "))
                                }
                            }
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Budget:")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(fetched.budget)
                                }
                                VStack(alignment: .leading) {
                                    Text("Box Office:")
                                        .fontWeight(.bold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(fetched.boxOffice)
                                }
                            }
                        }
                        Spacer()
                        Text(fetched.description)
                    }.padding()
                }
            }
        }.onDisappear { model.disconnect() }
    }
}

struct PosterView: View, Renderer {
    @ModelState var model: FetchableWithPlaceholder<UIImage, UIImage>
    init(modelState: ModelState<FetchableWithPlaceholder<UIImage, UIImage>>) {
        _model = modelState
    }
    var body: some View {
        Image(uiImage: model.fetched?.value ?? model.placeholder).resizable()
    }
}

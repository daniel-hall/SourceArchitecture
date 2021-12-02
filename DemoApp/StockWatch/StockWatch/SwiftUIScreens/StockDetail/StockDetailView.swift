//
//  StockDetailView.swift
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

import SwiftUI
import SourceArchitecture


protocol StockDetailViewDependency {
    var stockDetailViewSource: Source<StockDetailView.RenderedModel> { get }
}

extension StockDetailView {
    struct Model {
        let symbol: String
        let companyName: String
        let companyDescription: String
        let ceoName: String
        let numberOfEmployees: String
        let marketCap: String
        let logoSource: Source<Fetchable<UIImage?>>
        let isWatched: Bool
        let toggleWatched: Action<Void>
    }
}

struct StockDetailView: View, Renderer {
    typealias Dependencies = StockDetailViewDependency
    @ObservedObject var source: AnySource<Fetchable<Model>>

    init(dependencies: Dependencies) {
        source = dependencies.stockDetailViewSource
    }

    var body: some View {
        Group {
            switch model.asFetchable() {
            case .fetching(let fetching):
                FetchableFetchingView(fetching) { FetchedView() }
                .navigationTitle("")
            case .failure(let failure):
                FetchableErrorView(failure) { FetchedView() }
                .navigationTitle("")
            case .fetched(let fetched):
                FetchedView(fetched).transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    .navigationTitle(fetched.symbol)
            }
        }
        .ignoresSafeArea(.all, edges: .all)
    }
}

extension StockDetailView {
    struct FetchedView: View {
        private let model: StockDetailView.RenderedModel.Fetched?
        @ObservedObject var imageSource: AnySource<Fetchable<UIImage?>>
        @State var buttonAnimation: Animation? = nil

        init(_ model: StockDetailView.RenderedModel.Fetched? = nil) {
            self.model = model
            imageSource = model?.logoSource ?? .fromValue(.fetching(.init(progress: nil)))
        }

        var body: some View {
            ScrollView {
                VStack {
                    VStack(spacing: 6) {
                        Image(uiImage: imageSource.model.fetched?.value ?? .init())
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 100, height: 100)
                        Text(model?.symbol ?? "---").font(.title)
                        Text(model?.companyName ?? "---")
                            .multilineTextAlignment(.center)
                            .font(.headline)
                            .padding(.horizontal)
                            .lineLimit(nil)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CEO").fontWeight(.semibold)
                            Text(model?.ceoName ?? "--")
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("# of Employees").fontWeight(.semibold)
                            Text(model?.numberOfEmployees ?? "--")
                        }
                    }.padding()
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Market Capitalization").fontWeight(.semibold)
                            Text(model?.marketCap ?? "$--")
                        }
                        Spacer()
                    }
                    .padding()
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Description").fontWeight(.semibold)
                            Spacer()
                        }
                        Text(model?.companyDescription ?? "")
                    }
                    .padding()
                    VStack(alignment: .center) {
                        Text(model?.isWatched == true ? " Unwatch " : " Watch ")
                            .foregroundColor(.clear)
                            .padding(.init(top: 10, leading: 22, bottom: 10, trailing: 22))
                            .background {
                                Button(action: {
                                    try? model?.toggleWatched()
                                }) {
                                    ZStack {
                                        Color(.init(gray: 0, alpha: 0))
                                        switch model?.isWatched {
                                        case true: Text(" Unwatch ").foregroundColor(.red).transition(.opacity).id(UUID())
                                        default: Text(" Watch ").foregroundColor(.accentColor).transition(.opacity).id(UUID())
                                        }
                                    }
                                }
                            }
                    }
                    .animation(buttonAnimation, value: model?.isWatched)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .tint(model?.isWatched == true ? .red : nil)
                    .padding(18)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 100)
            }.onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    buttonAnimation = .interpolatingSpring(mass: 1, stiffness: 6, damping: 1.8, initialVelocity: 0.8).speed(8)
                }
            }
        }
    }
}

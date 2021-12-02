//
//  StockSearchView.swift
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

import Foundation
import SwiftUI
import SourceArchitecture


protocol StockSearchViewDependency {
    var stockSearchViewSource: Source<StockSearchView.RenderedModel> { get }
}

extension StockSearchView {
    struct Model {
        let searchTerm: String?
        let symbols: Array<Source<StockCellView.RenderedModel>>
        let search: Action<String?>
    }
}

struct StockSearchView: View, Renderer {
    typealias Dependencies = StockSearchViewDependency & StockDetailViewDependency
    private let dependencies: Dependencies
    
    @Binding private(set) var searchTerm: String
    @ObservedObject var source: AnySource<Fetchable<Model>>
    
    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        let source = dependencies.stockSearchViewSource
        self._searchTerm = .init(get: { source.model.fetched?.searchTerm ?? ""
        }, set: {
            try? source.model.fetched?.search($0) }
        )
        self.source = source
    }
    var body: some View {
        Group {
            switch model {
            case .fetching: Text("Fetching")
            case .failure(let failure): Text(failure.error.localizedDescription)
            case .fetched(let fetched):
                List(fetched.symbols) { source in
                    StockCellView(source: source).background(
                        NavigationLink("", destination: StockDetailView(dependencies: dependencies)
                                        .onAppear {
                                            try? source.model.connected?.value.placeholder.select()
                                        }
                                      ).opacity(0)
                    )
                }
                .listStyle(.plain)
                .id(UUID())
                .searchable(text: $searchTerm, placement: .navigationBarDrawer(displayMode: .always))
                .disableAutocorrection(true)
            }
        }
        .navigationTitle("Symbols")
        .navigationBarTitleDisplayMode(.inline)
    }
}


extension StockCellView {
    struct Model {
        let price: String
        let lastUpdatedDate: Date
    }
    
    struct Placeholder {
        let isWatchlisted: Bool
        let toggleWatched: Action<Void>
        let select: Action<Void>
    }
    
    struct Symbol {
        let symbol: String
        let name: String
    }
}

extension StockCellView.Symbol: Identifiable {
    public var id: String { symbol }
}

struct StockCellView: View, Renderer {
    @StateObject var pulse = BackgroundPulseState()
    @ObservedObject var source: AnySource<ConnectableWithPlaceholder<FetchableWithPlaceholder<StockCellView.Model, StockCellView.Placeholder>, Symbol>>
    
    init(source: AnySource<RenderedModel>) {
        self.source = source
    }
    
    var body: some View {
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.placeholder.symbol)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(model.placeholder.name)
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer()
            switch model.connected?.value {
            case .fetched(let fetched):
                Text(fetched.value.price)
                    .font(.headline)
                    .foregroundColor(fetched.value.lastUpdatedDate.timeIntervalSinceNow > -90 ? .black : .gray)
            default:
                Text("$--.--").font(.headline).onDisappear {
                    if model.connected?.value.fetched?.lastUpdatedDate.timeIntervalSinceNow ?? -100 > -90 {
                        pulse.pulse()
                    }
                }
            }
            Button(action: {}) {
                Image(systemName: model.connected?.value.placeholder.isWatchlisted == true ? "checkmark.circle.fill" : "plus.circle")
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            .onTapGesture {
                pulse.stopPulsing()
                try? self.model.connected?.value.placeholder.toggleWatched()
            }
            .foregroundColor(.green)
        }
        .padding(.vertical, 5)
        .background(pulse.backgroundView)
        .onAppear {
            // Don't allow immediate pulse on appearance, only on meaningful changes
            pulse.disable()
            pulse.enable(after: 0.25)
            try? model.connect()
        }
        .onDisappear {
            pulse.disable()
            try? model.disconnect()
        }
        .onChange(of: model.connected?.value.fetched?.lastUpdatedDate) { [captureDate = model.connected?.value.fetched?.lastUpdatedDate, captureModel = model] in
            guard let currentDate = $0 else { return }
            if currentDate.timeIntervalSinceNow < -90, case .fetched(let fetched) = model.connected?.value {
                try? fetched.refresh()
                pulse.enable()
            }
            if (captureDate != nil) && (currentDate != captureDate || captureModel.connected?.value == nil) {
                pulse.enable()
                pulse.pulse()
            }
        }
    }
}

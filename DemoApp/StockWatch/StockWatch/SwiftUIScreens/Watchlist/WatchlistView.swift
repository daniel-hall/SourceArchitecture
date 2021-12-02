//
//  WatchlistView.swift
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


protocol WatchlistViewDependency {
    var watchlistViewSource: Source<WatchlistView.RenderedModel> { get }
}

extension WatchlistView {
    struct Model {
        let watchedStocks: [Source<WatchlistViewCell.RenderedModel>]
        let unwatch: Action<WatchlistViewCell.Placeholder>
        let select: Action<WatchlistViewCell.Placeholder>
    }
}

struct WatchlistView: View, Renderer {
    typealias Dependencies = WatchlistViewDependency & StockDetailView.Dependencies
    private let dependencies: Dependencies
    @State var changeType: WatchlistViewCell.ChangeType = .amount

    @ObservedObject var source: AnySource<Model>

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        source = dependencies.watchlistViewSource
    }
    var body: some View {
        List(model.watchedStocks) { source in
            WatchlistViewCell(source: source, changeType: changeType).background(
                NavigationLink("", destination: StockDetailView(dependencies: dependencies)
                                .onAppear {
                                    try? self.model.select(source.model.placeholder)
                                }
                                .navigationTitle(source.model.placeholder.symbol)
                              ).opacity(0)
            ).swipeActions {
                Button("Unwatch") {
                    try? model.unwatch(source.model.placeholder)
                }
                .tint(.red)
            }
        }.animation(.spring(), value: model.watchedStocks.count)
            .listStyle(.plain)
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        changeType = changeType == .percent ? .amount : .percent
                    }) {
                        Text(changeType == .percent ? "$" : "%")
                            .foregroundColor(.gray)
                            .frame(width: 100, height: 100, alignment: .trailing)
                    }
                }
            }
    }
}

extension WatchlistViewCell {
    struct Model {
        let price: String
        let percentChange: String
        let amountChange: String
        let trend: Trend
        let lastUpdatedDate: Date

        enum Trend {
            case up, down
        }
    }

    enum ChangeType {
        case amount, percent
    }

    struct Placeholder {
        let symbol: String
        let name: String
    }
}

extension WatchlistViewCell.Placeholder: Identifiable {
    public var id: String { symbol }
}


struct WatchlistViewCell: View, Renderer {
    private let changeType: ChangeType
    @StateObject var pulse = BackgroundPulseState()
    @State var hasAppeared = false

    @ObservedObject var source: AnySource<ConnectableWithPlaceholder<Fetchable<Model>, Placeholder>>

    init(source: AnySource<RenderedModel>, changeType: ChangeType) {
        self.changeType = changeType
        self.source = source
    }

    var body: some View {
        if hasAppeared {
            if !model.isConnected {
                pulse.disable()
                try? model.connect()
            }
        }
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
            VStack(alignment: .trailing, spacing: 2) {
                switch model.connected?.value {
                case .fetched(let fetched):
                    Group {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Image(systemName: fetched.trend == .up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 11, weight: .ultraLight))
                            Text(changeType == .percent ? fetched.percentChange : fetched.amountChange)
                                .font(.system(size: 14, weight: .light))
                        }
                        Text(fetched.value.price)
                            .font(.headline)
                            .foregroundColor(fetched.value.lastUpdatedDate.timeIntervalSinceNow > -90 ? (fetched.trend == .up ? .green : .red) : .gray)
                    }.foregroundColor(fetched.value.lastUpdatedDate.timeIntervalSinceNow > -90 ? (fetched.trend == .up ? .green : .red) : .gray)
                default:
                    Text("$--.--").font(.headline).onDisappear {
                        if model.connected?.value.fetched?.lastUpdatedDate.timeIntervalSinceNow ?? -100 > -90 {
                            pulse.pulse()
                        }
                    }
                }
            }
            .alignmentGuide(VerticalAlignment.center) { $0.height * 0.65 }
        }
        .padding(.vertical, 4)
        .background(pulse.backgroundView)
        .onAppear {
            // Don't allow immediate pulse on appearance, only on meaningful changes
            pulse.disable()
            pulse.enable(after: 0.25)
            if !hasAppeared {
                hasAppeared = true
            }
            try? model.connect()
        }
        .onDisappear {
            if hasAppeared {
                hasAppeared = false
            }
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

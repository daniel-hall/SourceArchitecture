//
//  StandardFetchableViews.swift
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
import Combine
import Foundation
import SourceArchitecture


struct FetchableErrorView<Value, Content: View>: View {
    let model: Fetchable<Value>.Failure
    let shouldShowRetryButton: Bool
    let content: () -> Content
    init(_ model: Fetchable<Value>.Failure, shouldShowRetryButtonIfAvailable: Bool = true, @ViewBuilder displayedOver content: @escaping () -> Content) {
        self.model = model
        self.shouldShowRetryButton = shouldShowRetryButtonIfAvailable
        self.content = content
    }
    init(_ model: Fetchable<Value>.Failure, shouldShowRetryButtonIfAvailable: Bool = true) where Content == EmptyView {
        self.model = model
        self.shouldShowRetryButton = shouldShowRetryButtonIfAvailable
        self.content = { EmptyView() }
    }
    
    var body: some View {
        content().overlayWithBlur {
            VStack {
                Text("Error: \(model.error.localizedDescription)")
                    .font(.headline)
                    .padding(40)
                if shouldShowRetryButton {
                    Button("Retry") { try? model.retry?() }
                }
            }
        }.transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.25).delay(0.5)), removal: .opacity.animation(.easeInOut(duration: 0.3)) ))
    }
}

struct FetchableFetchingView<Value, Content: View>: View {
    @ObservedObject var progress: AnySource<SourceArchitecture.Progress>
    let model: Fetchable<Value>.Fetching
    let content: () -> Content
    let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }()
    
    init(_ model: Fetchable<Value>.Fetching, @ViewBuilder displayedOver content: @escaping () -> Content) {
        self.model = model
        progress = model.progress ?? .fromValue(.init(totalUnits: 0, completedUnits: 0, fractionCompleted: 0, estimatedTimeRemaining: 0))
        //        (model.progress ?? SingleValueSource(FetchableProgress(totalUnits: 0, completedUnits: 0, fractionCompleted: 0, estimatedTimeRemaining: nil))).rendered()
        self.content = content
    }
    init(_ model: Fetchable<Value>.Fetching, shouldShowRetryButtonIfAvailable: Bool = true) where Content == EmptyView {
        self.model = model
        progress = model.progress ?? .fromValue(.init(totalUnits: 0, completedUnits: 0, fractionCompleted: 0, estimatedTimeRemaining: 0))
        //        self._progress = (model.progress ?? SingleValueSource(FetchableProgress(totalUnits: 0, completedUnits: 0, fractionCompleted: 0, estimatedTimeRemaining: nil))).rendered()
        self.content = { EmptyView() }
    }
    
    var body: some View {
        content().overlayWithBlur {
            VStack {
                Text("Fetching...")
                    .font(.headline)
                    .padding(12)
                ProgressView()
                    .scaleEffect(2, anchor: .center)
                    .padding()
                formatter.string(from: NSNumber(value: progress.model.fractionCompleted)).map { Text($0) }
            }
        }.transition(.asymmetric(insertion: .opacity.animation(.easeIn(duration: 0.25).delay(0.5)), removal: .opacity.animation(.easeInOut(duration: 0.3)) ))
    }
}

fileprivate extension View {
    func overlayWithBlur<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        self.overlay {
            ZStack {
                Color(.init(gray: 0, alpha: 0)).ignoresSafeArea()
                content()
            }.background(.ultraThinMaterial)
        }
    }
}

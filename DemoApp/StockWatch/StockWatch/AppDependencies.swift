//
//  AppDependencies.swift
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

import UIKit
import SourceArchitecture
import SwiftUI


// This is where dependencies that will be injected throughout the app are defined and initialized. This file can be considered the Dependency Injector for all VCs and Views that are created in the app and the Source for any screen can be controlled from here. Mock dependencies for the network, file system, etc. can be plugged in here and used throughout the app for UI testing, etc.

private let appDependencies = AppDependencies(coreDependencies: CoreDependencies())

struct AppDependencies: MainTabView.Dependencies {
    fileprivate let coreDependencies: CoreDependencies
    var watchlistViewSource: Source<WatchlistView.RenderedModel>
    var stockSearchViewSource: Source<StockSearchView.RenderedModel>
    let stockDetailViewSource: Source<StockDetailView.RenderedModel>
    
    init(coreDependencies: CoreDependencies) {
        self.coreDependencies = coreDependencies
        watchlistViewSource = WatchlistViewSource(dependencies: coreDependencies)
        stockSearchViewSource = StockSearchViewSource(dependencies: coreDependencies)
        stockDetailViewSource = StockDetailViewSource(dependencies: coreDependencies)
    }
}


// MARK: - View Controller Injections -


extension UIViewController {
    @IBSegueAction func watchlistScreen(_ coder: NSCoder) -> WatchlistViewController? {
        WatchlistViewController(source: WatchlistViewControllerSource(dependencies: appDependencies.coreDependencies), coder: coder)
    }
}

extension UIViewController {
    @IBSegueAction func stockSearchScreen(_ coder: NSCoder) -> StockSearchViewController? {
        StockSearchViewController(source: StockSearchViewControllerSource(dependencies: appDependencies.coreDependencies), coder: coder)
    }
}

extension UIViewController {
    @IBSegueAction func stockDetailScreen(_ coder: NSCoder) -> StockDetailViewController? {
        StockDetailViewController(source: StockDetailViewControllerSource(dependencies: appDependencies.coreDependencies), coder: coder)
    }
}


// Include the Main Hosting Controller for the SwiftUI implementation here, so it can access the fileprivate appDependencies instance
final class MainHostingController: UIHostingController<MainTabView> {
    init() {
        super.init(rootView: MainTabView(dependencies: appDependencies))
    }
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: MainTabView(dependencies: appDependencies))
    }
}

//
//  MainViewController.swift
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
import SwiftUI
import Combine


final class MainViewController: UIViewController, UITabBarControllerDelegate {
    private let hostingController: MainHostingController
    private var tabController: UITabBarController?
    private var subscription: AnyCancellable?
    @IBOutlet private var container: UIView!

    required init?(coder: NSCoder) {
        hostingController = MainHostingController()
        super.init(coder: coder)
        subscription = MainTabView.switchToUIKitSignal.sink { [weak self] in
            self?.switchToUIKit()
        }
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController is EmptyViewController {
            switchToSwiftUI()
            return false
        }
        return true
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let tab = segue.destination as? UITabBarController, tabController == nil {
            tabController = tab
            tabController?.delegate = self
        }
    }

    func switchToUIKit() {
        guard let tabController = tabController else {
            return
        }
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        addChild(tabController)
        tabController.view.translatesAutoresizingMaskIntoConstraints = false
        tabController.view.frame = container.frame
        container.addSubview(tabController.view)
        tabController.view.leftAnchor.constraint(equalTo: container.leftAnchor).isActive = true
        tabController.view.rightAnchor.constraint(equalTo: container.rightAnchor).isActive = true
        tabController.view.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        tabController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        tabController.didMove(toParent: self)
    }

    func switchToSwiftUI() {
        tabController?.willMove(toParent: nil)
        tabController?.view.removeFromSuperview()
        tabController?.removeFromParent()
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.frame = container.frame
        addChild(hostingController)
        container.addSubview(hostingController.view)
        hostingController.view.leftAnchor.constraint(equalTo: container.leftAnchor).isActive = true
        hostingController.view.rightAnchor.constraint(equalTo: container.rightAnchor).isActive = true
        hostingController.view.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        hostingController.didMove(toParent: self)
    }
}

final class EmptyViewController: UIViewController {}

struct MainTabView: View {
    fileprivate static var switchToUIKitSignal = PassthroughSubject<Void, Never>()
    typealias Dependencies = WatchlistTab.Dependencies & StockSymbolsTab.Dependencies
    let dependencies: Dependencies
    @State private var selectedItem = "watchlist"
    @State private var oldSelectedItem = "watchlist"
    var body: some View {
        TabView(selection: $selectedItem) {
            WatchlistTab(dependencies: dependencies)
                .tag("watchlist")
            StockSymbolsTab(dependencies: dependencies)
                .tag("symbols")
            Text(".")
                .tag("switch")
                .tabItem {
                    Label("Switch to UIKit", systemImage: "repeat")
                }
        }.onChange(of: selectedItem) {
            if $0 == "switch" {
                Self.switchToUIKitSignal.send()
                selectedItem = oldSelectedItem
            } else {
                oldSelectedItem = selectedItem
            }
        }
    }
}

struct WatchlistTab: View {
    typealias Dependencies = WatchlistView.Dependencies
    let dependencies: Dependencies
    var body: some View {
        NavigationView {
            WatchlistView(dependencies: dependencies)
        }
        .navigationViewStyle(.stack)
        .tabItem {
            Label("Watchlist", systemImage: "list.star")
        }
    }
}

struct StockSymbolsTab: View {
    typealias Dependencies = StockSearchView.Dependencies
    let dependencies: Dependencies
    var body: some View {
        NavigationView {
            StockSearchView(dependencies: dependencies)
        }
        .navigationViewStyle(.stack)
        .tabItem {
            Label("Search", systemImage: "magnifyingglass")
        }
    }
}

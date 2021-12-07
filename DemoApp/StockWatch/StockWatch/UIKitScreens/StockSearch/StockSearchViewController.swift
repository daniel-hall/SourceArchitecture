//
//  StockSearchViewController.swift
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


extension StockSearchViewController {
    struct Model {
        var searchTerm: String?
        var symbols: Array<Source<StockSearchCell.RenderedModel>>
        var search: Action<String?>
    }
}

final class StockSearchViewController: UIViewController, Renderer {
    @IBOutlet private var tableView: UITableView!
    private let searchController = UISearchController(searchResultsController: nil)
    private var observers = [AnyObject]()
    
    public let source: AnySource<Fetchable<Model>>
    
    init?(source: AnySource<RenderedModel>, coder: NSCoder) {
        self.source = source
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Can't initialize \(Self.self) without a Source")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Setup Keyboard avoidance so the last rows of the table aren't covered by the keyboard
        observers = [NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] in
            if let keyboardHeight = ($0.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue.height {
                self?.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardHeight + 12, right: 0)
            }
        },
                     NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { [weak self] _ in
            self?.tableView.contentInset = .zero
        }
        ]
        source.subscribe(self)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.estimatedRowHeight = 100
        tableView.indexPathForSelectedRow.map { tableView.deselectRow(at: $0, animated: true) }
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = searchController
        tableView.visibleCells.forEach { cell in self.tableView(tableView, willDisplay: cell, forRowAt: tableView.indexPath(for: cell) ?? .init(row: 0, section: 0))
        }
    }
    
    func render() {
        switch model {
        case .failure(let error):
            if error.failedAttempts <= 3 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    try? error.retry?()
                }
            }
        case .fetching: break
        case .fetched(let fetched):
            searchController.searchResultsUpdater = nil
            searchController.searchBar.text = fetched.searchTerm
            searchController.searchResultsUpdater = self
            tableView.reloadData()
        }
    }
}

extension StockSearchViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.fetched?.symbols.count ?? 0
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "stockCell", for: indexPath) as? StockSearchCell, let symbols = self.model.fetched?.symbols, indexPath.row < symbols.count else {
            return UITableViewCell()
        }
        cell.setSource(symbols[indexPath.row])
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? StockSearchCell, let symbols = self.model.fetched?.symbols, symbols.count > indexPath.row {
            cell.setSource(symbols[indexPath.row])
        }
    }
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let symbols = self.model.fetched?.symbols, symbols.count > indexPath.row {
            try? symbols[indexPath.row].model.disconnect()
        }
    }
}

extension StockSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        try? (tableView.cellForRow(at: indexPath) as? StockSearchCell)?.model.connected?.value.placeholder.select()
    }
}

extension StockSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        try? model.fetched?.search(searchController.searchBar.text)
    }
}


extension StockSearchCell {
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


final class StockSearchCell: UITableViewCell, Renderer {
    @IBOutlet private var symbol: UILabel!
    @IBOutlet private var name: UILabel!
    @IBOutlet private var price: UILabel! { didSet { price.text = "— —" } }
    @IBOutlet private var watchlistButton: UIButton!
    private var isFirstRender = true
    private var lastSymbol = ""
    private var lastFetchedDate: Date?
    private var isSameSymbol = false
    
    var source: AnySource<ConnectableWithPlaceholder<FetchableWithPlaceholder<Model, Placeholder>, Symbol>> = .unsafelyInitialized()
    
    func setSource(_ source: AnySource<RenderedModel>) {
        self.source = source
        isSameSymbol = lastSymbol == model.placeholder.symbol
        lastSymbol = model.placeholder.symbol
        try? model.connect()
        source.subscribe(self)
    }
    
    func render() {
        symbol.text = model.placeholder.symbol
        name.text = model.placeholder.name
        watchlistButton.setImage(UIImage(systemName: model.connected?.value.placeholder.isWatchlisted == true ? "checkmark.circle.fill" : "plus.circle"), for: .normal)
        watchlistButton.isEnabled = model.isConnected
        switch model.connected?.value {
        case .fetched(let fetched):
            price.text = fetched.price
            price.textColor = .black
            if price.text != "— —", !isFirstRender, !isSameSymbol, lastFetchedDate != fetched.lastUpdatedDate {
                flash()
            }
            if fetched.lastUpdatedDate.timeIntervalSinceNow < -90 {
                price.textColor = .lightGray
                try? fetched.refresh()
                stopFlashing()
            }
            isFirstRender = false
            isSameSymbol = false
            lastFetchedDate = fetched.lastUpdatedDate
        default: break
        }
    }
    
    override func prepareForReuse() {
        try? model.disconnect()
        isFirstRender = true
        price.text = "— —"
        price.textColor = .lightGray
        stopFlashing()
    }
    
    @IBAction func toggleWatched() {
        try? model.connected?.value.placeholder.toggleWatched()
        stopFlashing()
    }
}

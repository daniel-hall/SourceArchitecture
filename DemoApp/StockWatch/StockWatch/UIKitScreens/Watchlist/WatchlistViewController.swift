//
//  WatchlistViewController.swift
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


extension WatchlistViewController {
    struct Model {
        let watchedStocks: [Source<WatchedStockCell.RenderedModel>]
        let unwatch: Action<WatchedStockCell.Placeholder>
        let select: Action<WatchedStockCell.Placeholder>
    }
}

final class WatchlistViewController: UIViewController, Renderer {
    @IBOutlet private var table: UITableView!
    @IBOutlet private var changeTypeButton: UIBarButtonItem!
    private var changeType: WatchedStockCell.ChangeType = .amount
    
    public let source: AnySource<Model>
    
    init?(source: AnySource<RenderedModel>, coder: NSCoder) {
        self.source = source
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        render()
    }
    
    func render() {
        let selected = table.indexPathForSelectedRow
        table.reloadData()
        table.selectRow(at: selected, animated: false, scrollPosition: .none)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        table.indexPathForSelectedRow.map { table.deselectRow(at: $0, animated: true) }
    }
    
    @IBAction func toggleChangeType(sender: UIBarButtonItem) {
        switch changeType {
        case .amount:
            changeType = .percent
            changeTypeButton.title = "$"
        case .percent:
            changeType = .amount
            changeTypeButton.title = "%"
        }
        table.visibleCells.forEach {
            ($0 as? WatchedStockCell)?.changeType = changeType
        }
    }
}

extension WatchlistViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.watchedStocks.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "watchedStockCell", for: indexPath) as? WatchedStockCell else { return UITableViewCell() }
        let source = model.watchedStocks[indexPath.row]
        cell.setSource(source)
        cell.changeType = changeType
        return cell
    }
}

extension WatchlistViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        .init(actions: [.init(style: .destructive, title: "Unwatch", handler: { [weak self] in
            guard let self = self else {
                $2(false)
                return
            }
            try? self.model.unwatch(self.model.watchedStocks[indexPath.row].model.placeholder)
            $2(true)
        })])
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        (cell as? WatchedStockCell)?.changeType = changeType
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        try? model.select(model.watchedStocks[indexPath.row].model.placeholder)
    }
}

extension WatchedStockCell {
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

final class WatchedStockCell: UITableViewCell, Renderer {
    @IBOutlet private var symbol: UILabel!
    @IBOutlet private var name: UILabel!
    @IBOutlet private var price: UILabel! { didSet { price.text = "— —" } }
    @IBOutlet private var amount: UILabel! { didSet { amount.text = "— —" } }
    @IBOutlet var changeArrow: UIImageView!
    public var changeType: ChangeType = .amount {
        didSet {
            render()
            stopFlashing()
        }
    }
    private var isFirstRender = true
    public var source: AnySource<FetchableWithPlaceholder<Model, Placeholder>> = .unsafelyInitialized()
    
    func setSource(_ source: AnySource<RenderedModel>) {
        self.source = source
        source.subscribe(self)
    }
    
    func render() {
        symbol.text = model.placeholder.symbol
        name.text = model.placeholder.name
        switch model {
        case .failure: break
        case .fetching: break
        case .fetched(let fetched):
            price.text = fetched.value.price
            changeArrow.image = fetched.value.trend == .up ? .init(systemName: "arrowtriangle.up.fill") : .init(systemName: "arrowtriangle.down.fill")
            amount.text = changeType == .amount ? fetched.value.amountChange : fetched.value.percentChange
            if price.text != "— —", !isFirstRender {
                flash()
            }
            if fetched.value.lastUpdatedDate.timeIntervalSinceNow < -90 {
                changeArrow.tintColor = .lightGray
                [price, amount].forEach { $0.textColor = .lightGray }
                try? model.fetched?.refresh()
                stopFlashing()
            } else {
                let color = fetched.value.trend == .up ? UIColor.systemGreen : .systemRed
                changeArrow.tintColor = color
                [price, amount].forEach { $0?.textColor = color
                }
            }
            isFirstRender = false
        }
    }
    
    override func prepareForReuse() {
        isFirstRender = true
        changeArrow.image = nil
        price.text = "— —"
        amount.text = "— —"
        stopFlashing()
    }
}

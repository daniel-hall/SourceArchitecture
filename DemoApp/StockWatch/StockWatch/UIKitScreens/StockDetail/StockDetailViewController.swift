//
//  StockDetailViewController.swift
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


public extension StockDetailViewController {
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

public class StockDetailViewController: UIViewController, Renderer {
    @IBOutlet private var logo: UIImageView!
    @IBOutlet private var symbol: UILabel!
    @IBOutlet private var companyName: UILabel!
    @IBOutlet private var ceoName: UILabel!
    @IBOutlet private var numberOfEmployees: UILabel!
    @IBOutlet private var marketCap: UILabel!
    @IBOutlet private var companyDescription: UILabel!
    @IBOutlet private var loadingView: UIView!
    @IBOutlet private var loadingProgress: UIProgressView!
    @IBOutlet private var errorView: UIView!
    @IBOutlet private var errorDetail: UILabel!
    @IBOutlet private var watchlistButton: UIButton!

    public var source: AnySource<Fetchable<Model>>

    init?(source: AnySource<RenderedModel>, coder: NSCoder) {
        self.source = source
        super.init(coder: coder)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Can't initialize \(Self.self) without a Rendered Model")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }

    // Virtually all the work a VC does is render the model to appropriate views and properties, and handle user input by calling actions on the model.
    public func render() {
        navigationItem.title = ""
        [errorView, loadingView, watchlistButton].forEach { $0?.isHidden = true }
        switch model {
        case .fetching(let fetching):
            symbol.text = "---"
            companyName.text = "--"
            loadingView.isHidden = false
            loadingProgress.progress = fetching.progress?.model.fractionCompleted ?? 0
            fetching.progress?.subscribe(self)
        case .failure(let error):
            errorView.isHidden = false
            errorDetail.text = error.error.localizedDescription
        case .fetched(let fetched):
            navigationItem.title = fetched.symbol
            symbol.text = fetched.symbol
            companyName.text = fetched.companyName
            companyDescription.text = fetched.companyDescription
            marketCap.text = fetched.marketCap
            numberOfEmployees.text = fetched.numberOfEmployees
            ceoName.text = fetched.ceoName
            watchlistButton.isHidden = false
            watchlistButton.setTitle(fetched.isWatched ? "Unwatch" : "Watch", for: .normal)
            watchlistButton.setTitleColor(fetched.isWatched ? .systemRed : .systemGreen, for: .normal)
            fetched.logoSource.model.fetched.map {
                logo.image = $0.value
            }
            fetched.logoSource.subscribe(self)
        }
    }

    @IBAction func retry() {
        if case .failure(let error) = model {
            try? error.retry?()
        }
    }

    @IBAction func toggleWatched() {
        try? model.fetched?.toggleWatched()
    }
}

//
//  MovieDetailsViewController.swift
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

import UIKit
import SourceArchitecture


final class MovieDetailsViewController: UIViewController, Renderer {

    @IBOutlet private var poster: UIImageView!
    @IBOutlet private var movieTitle: UILabel!
    @IBOutlet private var tagline: UILabel!
    @IBOutlet private var rating: UILabel!
    @IBOutlet private var releaseDate: UILabel!
    @IBOutlet private var director: UILabel!
    @IBOutlet private var topCast: UILabel!
    @IBOutlet private var budget: UILabel!
    @IBOutlet private var boxOffice: UILabel!
    @IBOutlet private var movieDescription: UILabel!

    @IBOutlet private var loadingView: UIView!
    @IBOutlet private var errorView: UIView!
    @IBOutlet private var errorMessage: UILabel!
    @IBOutlet private var retryButton: UIButton!

    @Sourced var model: Fetchable<MovieDetails>
    @Sourced() var fetchablePoster: FetchableWithPlaceholder<UIImage, UIImage>?

    init?(source: AnySource<Fetchable<MovieDetails>>, coder: NSCoder) {
        _model = .init(from: source)
        super.init(coder: coder)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }

    func render() {
        loadingView.isHidden = true
        errorView.isHidden = true
        switch model {
        case .fetching:
            loadingView.isHidden = false
        case .failure(let failure):
            errorView.isHidden = false
            errorMessage.text = failure.error.localizedDescription
            retryButton.isHidden = failure.retry == nil
        case .fetched(let fetched):
            _fetchablePoster.setSource(fetched.value.poster)
            title = fetched.value.title
            poster.image = fetchablePoster?.fetched?.value ?? fetchablePoster?.placeholder
            movieTitle.text = fetched.value.title
            tagline.text = fetched.value.tagline
            rating.text = fetched.value.rating
            releaseDate.text = fetched.value.releaseDate
            director.text = fetched.value.director
            topCast.text = fetched.value.topCast.joined(separator: ", ")
            budget.text = fetched.value.budget
            boxOffice.text = fetched.value.boxOffice
            movieDescription.text = fetched.value.description
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    @IBAction private func retry() {
        model.failure?.retry?()
    }
}

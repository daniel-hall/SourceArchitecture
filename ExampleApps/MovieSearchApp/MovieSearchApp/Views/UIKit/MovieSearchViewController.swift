//
//  MovieSearchViewController.swift
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


final class MovieSearchViewController: UIViewController, Renderer {

    @IBOutlet private var tableView: UITableView!
    @IBOutlet private var noResultsView: UIView!
    @IBOutlet private var loadingView: UIView!
    @IBOutlet private var errorView: UIView!
    @IBOutlet private var errorMessage: UILabel!
    @IBOutlet private var retryButton: UIButton!

    private let searchController = UISearchController(searchResultsController: nil)

    @Sourced var model: Fetchable<MovieSearch>

    init?(source: AnySource<Fetchable<MovieSearch>>, coder: NSCoder) {
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        tableView.indexPathForSelectedRow.map { tableView.deselectRow(at: $0, animated: true) }
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = searchController
        tableView.visibleCells.forEach { cell in self.tableView(tableView, willDisplay: cell, forRowAt: tableView.indexPath(for: cell) ?? .init(row: 0, section: 0))
        }
    }

    func render() {
        loadingView.isHidden = true
        errorView.isHidden = true
        noResultsView.isHidden = true
        switch model {
        case .fetching:
            loadingView.isHidden = false
        case .failure(let failure):
            errorView.isHidden = false
            errorMessage.text = failure.error.localizedDescription
            retryButton.isHidden = failure.retry == nil
        case .fetched(let fetched):
            searchController.searchResultsUpdater = nil
            searchController.searchBar.text = fetched.value.currentSearchTerm
            noResultsView.isHidden = !fetched.value.results.isEmpty
            tableView.reloadData()
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        (sender as? MovieCell)?.model?.select()
    }

    @IBAction private func retry() {
        model.failure?.retry?()
    }
}

extension MovieSearchViewController: UISearchBarDelegate {
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        model.fetched?.value.search(searchBar.text)
    }
}

extension MovieSearchViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return model.fetched?.value.results.count ?? 0
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "movieCell", for: indexPath) as? MovieCell, let results = self.model.fetched?.value.results, indexPath.row < results.count else {
            return UITableViewCell()
        }
        cell.setModel(SingleValueSource(results[indexPath.row]).eraseToAnySource())
        return cell
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let cell = cell as? MovieCell, let results = self.model.fetched?.value.results, results.count > indexPath.row {
            cell.setModel(SingleValueSource(results[indexPath.row]).eraseToAnySource())
            if indexPath.row > results.count - 10  {
                model.fetched?.value.loadMore?()
            }
        }
    }
}

extension MovieSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        model.fetched?.value.results[indexPath.row].select()
    }
}

final class MovieCell: UITableViewCell, Renderer {

    @IBOutlet var title: UILabel!
    @IBOutlet var rating: UILabel!
    @IBOutlet var date: UILabel!
    @IBOutlet var movieDescription: UILabel!
    @IBOutlet var poster: UIImageView!
    @Sourced() var model: MovieSearch.Result?
    @Sourced() var thumbnail: FetchableWithPlaceholder<UIImage, UIImage>?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setModel(_ source: AnySource<MovieSearch.Result>) {
        _model.setSource(source)
        _thumbnail.setSource(source.state.thumbnail)
        render()
    }

    func render() {
        title.text = model?.title
        rating.text = model?.rating
        date.text = model?.releaseDate
        movieDescription.text = model?.description
        poster.image = thumbnail?.fetched?.value ?? thumbnail?.placeholder
    }
}

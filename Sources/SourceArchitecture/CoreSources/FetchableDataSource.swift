//
//  SourceArchitecture
//
//  Copyright (c) 2023 Daniel Hall
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


private final class _FetchableDataSource: Source<Fetchable<Data>> {

    @ActionFromMethod(retry) var retryAction
    @ActionFromMethod(refresh) var refreshAction

    @Threadsafe var failedAttempts = 0
    @Threadsafe var dataTask: URLSessionDataTask?

    let urlRequest: URLRequest

    lazy var initialState: Fetchable<Data> = .fetching(.init(progress: ProgressSource(self.fetch().progress).eraseToAnySource()))

    init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }

    func fetch() -> URLSessionDataTask {
        let dataTask = URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            if let data = data {
                if (response as? HTTPURLResponse)?.statusCode == 429 {
                    self.failedAttempts += 1
                    self.state = .failure(.init(error: NSError(domain: "Network", code: 429), failedAttempts: self.failedAttempts, retry: self.retryAction))
                    return
                }
                self.failedAttempts = 0
                self.state = .fetched(.init(value: data, refresh: self.refreshAction))
            } else {
                self.failedAttempts += 1
                self.state = .failure(.init(error: error!, failedAttempts: self.failedAttempts, retry: self.retryAction))
            }
        }
        self.dataTask = dataTask
        dataTask.resume()
        return dataTask
    }

    func retry() {
        let dataTask = fetch()
        state = .fetching(.init(progress: ProgressSource(dataTask.progress).eraseToAnySource()))
    }

    func refresh() {
        _ = fetch()
    }
}

public extension AnySource where Model: FetchableWithPlaceholderRepresentable, Model.Value == Data {

    func jsonDecoded<T: Decodable>() -> AnySource<FetchableWithPlaceholder<T, Model.Placeholder>> {
        self.decoded { try JSONDecoder().decode(T.self, from: $0) }
    }

    func decoded<T>(using decoder: @escaping (Data) throws -> T) -> AnySource<FetchableWithPlaceholder<T, Model.Placeholder>> {
        var failedAttempts = 0
        return map {
            switch $0.asFetchableWithPlaceholder() {
            case .fetching(let fetching):
                failedAttempts = 0
                return .fetching(.init(placeholder: fetching.placeholder, progress: fetching.progress))
            case .fetched(let fetched):
                do {
                    return try .fetched(.init(placeholder: fetched.placeholder, value: decoder(fetched.value), refresh: fetched.refresh))
                } catch {
                    failedAttempts += 1
                    return .failure(.init(placeholder: fetched.placeholder, error: error, failedAttempts: failedAttempts, retry: fetched.refresh))
                }
            case .failure(let failure):
                failedAttempts = failure.failedAttempts
                return .failure(.init(placeholder: failure.placeholder, error: failure.error, failedAttempts: failedAttempts, retry: failure.retry))
            }
        }
    }
}

public extension AnySource where Model: FetchableRepresentable, Model.Value == Data {
    @_disfavoredOverload
    func jsonDecoded<T: Decodable>() -> AnySource<Fetchable<T>> {
        self.decoded() { try JSONDecoder().decode(T.self, from: $0) }
    }

    @_disfavoredOverload
    func decoded<T>(using decoder: @escaping (Data) throws -> T) -> AnySource<Fetchable<T>> {
        var failedAttempts = 0
        return map {
            switch $0.asFetchable() {
            case .fetching(let fetching):
                failedAttempts = 0
                return .fetching(.init(progress: fetching.progress))
            case .fetched(let fetched):
                do {
                    return try .fetched(.init(value: decoder(fetched.value), refresh: fetched.refresh))
                } catch {
                    failedAttempts += 1
                    return .failure(.init(error: error, failedAttempts: failedAttempts, retry: fetched.refresh))
                }
            case .failure(let failure):
                failedAttempts = failure.failedAttempts
                return .failure(.init(error: failure.error, failedAttempts: failedAttempts, retry: failure.retry))
            }
        }
    }
}

/// Create a Source that fetches Data from a URLRequest
public final class FetchableDataSource: ComposedSource<Fetchable<Data>> {
    public init(urlRequest: URLRequest) {
        super.init { _FetchableDataSource(urlRequest: urlRequest).eraseToAnySource() }
    }
}

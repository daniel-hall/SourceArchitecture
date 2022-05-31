//
//  FetchableDataSource.swift
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

import Foundation


public final class FetchableDataSource: CustomSource {
    public class Actions: ActionMethods {
        fileprivate var retry = ActionMethod(FetchableDataSource.retry)
        fileprivate var refresh = ActionMethod(FetchableDataSource.refresh)
    }

    public class Threadsafe: ThreadsafeProperties {
        fileprivate var failedAttempts = 0
        fileprivate var dataTask: URLSessionDataTask?
    }

    public lazy var defaultModel: Fetchable<Data> = .fetching(.init(progress: ProgressSource(progress: fetch().progress).eraseToSource()))

    private let urlRequest: URLRequest

    public init(urlRequest: URLRequest) {
        self.urlRequest = urlRequest
    }

    private func fetch() -> URLSessionDataTask {
        let dataTask = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let data = data {
                if (response as? HTTPURLResponse)?.statusCode == 429 {
                    self.model = .failure(.init(error: NSError(domain: "Network", code: 429), failedAttempts: self.threadsafe.failedAttempts, retry: self.actions.retry))
                    return
                }
                self.threadsafe.failedAttempts = 0
                self.model = .fetched(.init(value: data, refresh: self.actions.refresh))
            } else {
                self.threadsafe.failedAttempts += 1
                self.model = .failure(.init(error: error!, failedAttempts: self.threadsafe.failedAttempts, retry: self.actions.retry))
            }
        }
        defer { dataTask.resume() }
        threadsafe.dataTask = dataTask
        return dataTask
    }

    fileprivate func retry() {
        let dataTask = fetch()
        model = .fetching(.init(progress: ProgressSource(progress: dataTask.progress).eraseToSource()))
    }

    fileprivate func refresh() {
        _ = fetch()
    }
}

public extension Source where Model: FetchableWithPlaceholderRepresentable, Model.Value == Data {

    func jsonDecoded<T: Decodable>() -> Source<FetchableWithPlaceholder<T, Model.Placeholder>> {
        self.decoded { try JSONDecoder().decode(T.self, from: $0) }
    }

    func decoded<T>(using decoder: @escaping (Data) throws -> T) -> Source<FetchableWithPlaceholder<T, Model.Placeholder>> {
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

public extension Source where Model: FetchableRepresentable, Model.Value == Data {
    @_disfavoredOverload
    func jsonDecoded<T: Decodable>() -> Source<Fetchable<T>> {
        self.decoded() { try JSONDecoder().decode(T.self, from: $0) }
    }

    @_disfavoredOverload
    func decoded<T>(using decoder: @escaping (Data) throws -> T) -> Source<Fetchable<T>> {
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

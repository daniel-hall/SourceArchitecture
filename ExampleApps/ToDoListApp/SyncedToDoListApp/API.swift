//
//  API.swift
//  SyncedToDoListApp
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
import SourceArchitecture
import ToDoList


/// Define the API endpoints for getting and updates the synced ToDoList
struct API {
    
    static func getToDoList() -> Source<Fetchable<ToDoList?>> {
        var urlRequest = URLRequest(url: .init(string: "https://62843b0f3060bbd3473602a8.mockapi.io/ToDoList/1")!)
        urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        urlRequest.timeoutInterval = 5
        return FetchableDataSource(urlRequest: urlRequest).eraseToSource()
            .jsonDecoded()
            .mapFetchedValue { Optional($0) }
            .refreshing(every: 5)
            .retrying(.everyIntervalWithMaximum(.init(retryInterval: 5, maximumRetries: 30)), forwardErrorAfter: .never)
    }

    static func updateToDoList(_ list: ToDoList) -> Source<Fetchable<ToDoList>> {
        var urlRequest = URLRequest(url: .init(string: "https://62843b0f3060bbd3473602a8.mockapi.io/ToDoList/1")!)
        urlRequest.httpMethod = "PUT"
        urlRequest.timeoutInterval = 5
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        urlRequest.httpBody = try! JSONEncoder().encode(list)
        return FetchableDataSource(urlRequest: urlRequest)
            .eraseToSource()
            .fetchAfterDelay(of: 1)
            .mapFetchedValue { _ in list }
            .retrying(.everyIntervalWithMaximum(.init(retryInterval: 5, maximumRetries: 30)), forwardErrorAfter: .never)
    }
}

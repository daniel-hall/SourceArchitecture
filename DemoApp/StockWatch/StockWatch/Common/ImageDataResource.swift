//
//  ImageDataResource.swift
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

import SourceArchitecture
import UIKit


/// A generic resource definition for fetching and caching image data from remote URLs
struct ImageDataResource: NetworkResource, CacheResource, FileResource {
    typealias Value = Data
    let url: URL
    var networkURLRequest: URLRequest { URLRequest(url: url) }
    let networkRequestTimeout: TimeInterval?
    var cacheIdentifier: String { "cachedImage-\(url.absoluteString)" }
    var filePath: String { "cachedImages/\(url.absoluteString)" }
    
    init(url: URL, timeout: TimeInterval = 15) {
        self.url = url
        self.networkRequestTimeout = timeout
    }
    func decode(data: Data, response: URLResponse) throws -> Data {
        return data
    }
}

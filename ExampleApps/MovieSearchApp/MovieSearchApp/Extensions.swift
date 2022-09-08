//
//  Extensions.swift
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


extension UIImage: CacheSizeRepresentable {
    public var cacheSize: Int {
        (cgImage?.bytesPerRow ?? 0) * (cgImage?.height ?? 0)
    }
}

/// Add the ability for a struct to implement lazy stored properties. Will be updated in the future to support copy-on-write mutations to lazy stored values
protocol LazyStoring {
    var _storage: LazyStorage { get }
}

extension LazyStoring {
    func lazy<T>(_ key: String = "\(#line).\(#column)", closure: () -> T) -> T {
        var existing: T? = _storage[key]
        if existing == nil {
            existing = closure()
            _storage[key] = existing!
        }
        return existing!
    }
}

class LazyStorage {
    private var storage = [String: Any]()
    fileprivate subscript<T>(key: String) -> T? {
        get { storage[key] as? T }
        set { storage[key] = newValue }
    }
}

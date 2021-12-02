//
//  SingleValueSource.swift
//  SourceArchitecture
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

import Foundation


final private class SingleValueSource<Model>: Source<Model> {
    private let state: State
    public init(value: Model) {
        state = .init(model: value)
        super.init(state)
    }
}


public extension SourceProtocol where SourceType == Self {
    /// Creates a Source with a single, non-updating Model value
    static func fromValue(_ value: Model) -> Source<Model> {
        SingleValueSource(value: value) as Source<Model>
    }
}

public extension AnySourceProtocol where SourceType == Self {
    /// Creates an AnySource with a single, non-updating Model value
    static func fromValue(_ value: Model) -> AnySource<Model> {
        SingleValueSource(value: value) as AnySource<Model>
    }
}

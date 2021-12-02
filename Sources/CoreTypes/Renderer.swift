//
//  Renderer.swift
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
import SwiftUI


public protocol Renderer {
    /// An associated Model type that the Renderer defines to describe what data it expects to present and what Actions it expects to invoke
    associatedtype Model = RenderedModel
    
    /// Sometimes a Renderer needs to render an array of its Model, a Connectable version of its Model, etc. Whatever context / wrappers like this surround its core model represent its actual RenderedModel
    associatedtype RenderedModel
    
    /// A Source of the model that this Renderer will render.
    var source: AnySource<RenderedModel> { get }
    
    /// The method which will get called when the Source updates
    func render()
}

public extension Renderer where Self: AnyObject {
    var model: RenderedModel {
        source.subscribe(self)
        return source.model
    }
}

public extension Renderer where Self: View {
    var model: RenderedModel {
        source.model
    }
}

public extension Renderer where Self: View {
    func render() {
        // no-op since SwiftUI views render via their body property and will get the update automatically
    }
}

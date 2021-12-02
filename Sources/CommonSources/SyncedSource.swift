//
//  SyncedSource.swift
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
import UIKit


/// A protocol that allows a mutable properties struct to provide the properties needed for being a SyncedSource
public protocol SyncedSourcePropertiesProvider {
    var syncProperties: SyncedSourceProperties { get set }
}

public struct SyncedSourceProperties {
    fileprivate var isModelDirty = false
    fileprivate var isCacheDirty = true
    public init() { }
}

open class SyncedSource<Model>: Source<Model> {
    private let setModelClosure: (Model) -> Void
    private let setModelDirty: (Bool) -> Void
    private let isModelDirty: () -> Bool
    private let setCacheDirty: (Bool) -> Void
    private let isCacheDirty: () -> Bool
    private var cacheSource: Source<Persistable<Model>>!
    public init<T: Source<Model>, U: SyncedSourcePropertiesProvider>(_ state: SourceMutableState<T, U>, dependencies: CacheDependency) where T: CacheResource, T.Value == Model {
        self.setModelClosure = state.setModel
        self.setModelDirty = { state.syncProperties.isModelDirty = $0 }
        self.setCacheDirty = { state.syncProperties.isCacheDirty = $0 }
        self.isModelDirty = { state.syncProperties.isModelDirty }
        self.isCacheDirty = { state.syncProperties.isCacheDirty }
        super.init(state)
        self.cacheSource = dependencies.cacheResource(self as! T)
        cacheSource.subscribe(self, method: SyncedSource.cacheUpdated)
        subscribe(self, method: SyncedSource.modelUpdated)
        if case .notFound = cacheSource.model {
            try? cacheSource.model.set(model)
        }
    }
    
    private func modelUpdated() {
        if !isModelDirty() {
            setModelDirty(true)
            return
        }
        setCacheDirty(false)
        try? cacheSource.model.set(model)
    }
    
    private func cacheUpdated() {
        if !isCacheDirty() {
            setCacheDirty(true)
            return
        }
        if case .found(let found) = cacheSource.model {
            setModelDirty(false)
            setModelClosure(found.value)
        }
    }
}

public extension SourceProtocol where Self: CacheResource {
    typealias Value = Model
}

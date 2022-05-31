//
//  WeakAtomicCollection.swift
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


/// A dictionary-like structure that holds a weak reference to its values and manages necessary locking / unlocking for thread-safe access
class WeakAtomicCollection<Key: Hashable, Value: AnyObject> {
    private struct Wrapper {
        weak var value: Value?
        init(value: Value?) {
            self.value = value
        }
    }
    private let lock = NSRecursiveLock()
    private var dictionary = [Key : Wrapper]()
    private var pruneWorkItem: DispatchWorkItem?
    
    var count: Int { dictionary.count }
    
    private func prune() {
        guard pruneWorkItem == nil else {
            lock.unlock()
            return
        }
        let pruneWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.dictionary = self.dictionary.filter { $0.value.value != nil }
            self.pruneWorkItem = nil
            self.lock.unlock()
        }
        self.pruneWorkItem = pruneWorkItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1, execute: pruneWorkItem)
    }
    
    func removeValue(forKey key: Key) {
        lock.lock()
        dictionary.removeValue(forKey: key)
        prune()
        lock.unlock()
    }
    
    subscript(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        prune()
        return dictionary[key]?.value
    }
    
    subscript(_ key: Key, or `init`: () -> Value) -> Value {
        lock.lock()
        var strongValue: Value?
        if dictionary[key]?.value == nil {
            strongValue = `init`()
            dictionary[key] = Wrapper(value: strongValue)
        }
        defer { lock.unlock() }
        prune()
        return dictionary[key]!.value!
    }
}

extension WeakAtomicCollection where Value == AnyObject {
    subscript<T>(_ key: Key) -> T? {
        lock.lock()
        defer { lock.unlock() }
        prune()
        return dictionary[key]?.value as? T
    }
    
    subscript<T>(_ key: Key, or `init`: () -> T) -> T {
        lock.lock()
        var strongValue: Value?
        if dictionary[key]?.value as? T == nil {
            strongValue = `init`() as AnyObject
            dictionary[key] = Wrapper(value: strongValue)
        }
        defer {
            strongValue = nil
            lock.unlock()
        }
        prune()
        return dictionary[key]?.value as! T
    }
}

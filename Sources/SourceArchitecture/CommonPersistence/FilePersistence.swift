//
//  FilePersistence.swift
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


/// A basic implementation of file-based persistence. Given a descriptor with the domain, directory and path for a file, this can read and write to it. Note that this implementation uses a weak dictionary which will hold a shared instance of the file data in memory as long as some client code is referencing it. When all references are released, the latest data will be written to file and released from memory. This optimization minimizes memory usage and synchronization requirements.
public class FilePersistence {

    public struct Descriptor<Value> {

        public let url: URL
        public let expireAfter: TimeInterval?
        fileprivate let decode: (Data) throws -> Value
        fileprivate let encode: (Value) throws -> Data

        public init(domainMask: FileManager.SearchPathDomainMask = .userDomainMask, directory: FileManager.SearchPathDirectory = .cachesDirectory, path: String, expireAfter: TimeInterval? = nil, encode: @escaping(Value) throws -> Data, decode: @escaping(Data) throws -> Value) {
            self.url = FileManager.default.urls(for: directory, in: domainMask).first!.appendingPathComponent(path)
            self.expireAfter = expireAfter
            self.encode = encode
            self.decode = decode
        }

        public init(url: URL, expireAfter: TimeInterval? = nil, encode: @escaping(Value) throws -> Data, decode: @escaping(Data) throws -> Value) {
            self.url = url
            self.expireAfter = expireAfter
            self.encode = encode
            self.decode = decode
        }
    }

    private let dictionary = WeakDictionary<String, AnyObject>()

    public init() { }

    public subscript<Value>(descriptor: Descriptor<Value>) -> Source<Persistable<Value>> {
        dictionary[descriptor.url.absoluteString] { FilePersistenceSource(descriptor: descriptor).eraseToSource() }
    }
}

private final class FilePersistenceSource<Value>: SourceOf<Persistable<Value>> {

    @Action(FilePersistenceSource.set) private var setAction
    @Action(FilePersistenceSource.clear) private var clearAction
    @Threadsafe private var expiredWorkItem: DispatchWorkItem?
    @Threadsafe private var saveWorkItem: DispatchWorkItem?
    @Threadsafe private var saveDate: Date = Date()
    fileprivate lazy var initialModel = Persistable<Value>.notFound(.init(set: setAction))
    private let descriptor: FilePersistence.Descriptor<Value>

    fileprivate init(descriptor: FilePersistence.Descriptor<Value>) {
        self.descriptor = descriptor
        super.init()
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: descriptor.url.path)
            let persistedDate = attributes[FileAttributeKey.modificationDate] as? Date ?? .distantPast
            let data = try descriptor.decode(Data(contentsOf: descriptor.url))
            var isExpired = { false }
            if let expireAfter = descriptor.expireAfter {
                isExpired = { expireAfter < Date.timeIntervalSinceReferenceDate - persistedDate.timeIntervalSinceReferenceDate }
                // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
                let refreshTime = (persistedDate.timeIntervalSinceReferenceDate + expireAfter) - Date.timeIntervalSinceReferenceDate
                if refreshTime > 0 {
                    let workItem = DispatchWorkItem {
                        [weak self] in
                        guard let self = self else { return }
                        if case .found(let found) = self.model, found.isExpired {
                            self.model = .found(found)
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + refreshTime, execute: workItem)
                    expiredWorkItem = workItem
                }
            }
            model = (.found(.init(value: data, isExpired: isExpired, set: setAction, clear: clearAction)))
        } catch {
            model = .notFound(.init(error: error, set: setAction))
        }
    }

    private func set(value: Value) {
        expiredWorkItem?.cancel()
        let saveDate = Date()
        self.saveDate = saveDate
        var isExpired = { false }
        if let expireAfter = descriptor.expireAfter {
            isExpired = {
                expireAfter < Date.timeIntervalSinceReferenceDate - saveDate.timeIntervalSinceReferenceDate
            }
            // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if case .found(let found) = self.model, found.isExpired {
                    self.model = .found(found)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + expireAfter, execute: workItem)
            expiredWorkItem = workItem
        }
        self.model = .found(.init(value: value, isExpired: isExpired, set: setAction, clear: clearAction))

        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let data = try descriptor.encode(value)
            let saveWorkItem: DispatchWorkItem = .init { [weak self] in
                guard let self = self else { return }
                do {
                    try FileManager.default.createDirectory(at: self.descriptor.url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                    try data.write(to: self.descriptor.url)
                    var attributes = try FileManager.default.attributesOfItem(atPath: self.descriptor.url.path)
                    attributes[FileAttributeKey.modificationDate] = saveDate
                    try? FileManager.default.setAttributes(attributes, ofItemAtPath: self.descriptor.url.path)
                } catch {
                    self.model = .notFound(.init(error: error, set: self.setAction))
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: saveWorkItem)
            self.saveWorkItem = saveWorkItem
        } catch {
            self.model = .notFound(.init(error: error, set: setAction))
        }
    }

    private func clear() {
        expiredWorkItem?.cancel()
        saveWorkItem?.cancel()
        model = .notFound(.init(set: setAction))
        try? FileManager.default.removeItem(at: descriptor.url)
    }
}

public extension FilePersistence.Descriptor where Value: Codable {
    init(domainMask: FileManager.SearchPathDomainMask = .userDomainMask, directory: FileManager.SearchPathDirectory = .cachesDirectory, path: String, expireAfter: TimeInterval? = nil) {
        self.init(domainMask: domainMask, directory: directory, path: path, expireAfter: expireAfter, encode: { try JSONEncoder().encode($0) }, decode: { try JSONDecoder().decode(Value.self, from: $0) })
    }
}

public extension FilePersistence.Descriptor where Value: Encodable {
    init(domainMask: FileManager.SearchPathDomainMask = .userDomainMask, directory: FileManager.SearchPathDirectory = .cachesDirectory, path: String, expireAfter: TimeInterval? = nil, decode: @escaping(Data) throws -> Value) {
        self.init(domainMask: domainMask, directory: directory, path: path, expireAfter: expireAfter, encode: { try JSONEncoder().encode($0) }, decode: decode)
    }
}

public extension FilePersistence.Descriptor where Value: Decodable {
    init(domainMask: FileManager.SearchPathDomainMask = .userDomainMask, directory: FileManager.SearchPathDirectory = .cachesDirectory, path: String, expireAfter: TimeInterval? = nil, encode: @escaping(Value) throws -> Data) {
        self.init(domainMask: domainMask, directory: directory, path: path, expireAfter: expireAfter, encode: encode, decode: { try JSONDecoder().decode(Value.self, from: $0) })
    }
}

//
//  FileDependency.swift
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


/// Expresses dependency on a File persistence mechanism (e.g. the platform file system) that can return an updating Source of a Persistable<Value> for a specified FileResource
public protocol FileDependency {
    func fileResource<T: FileResource>(_ resource: T) -> Source<Persistable<T.Value>>
    func fileResourceElement<T: ResourceElement>(_ resource: T) -> Source<Persistable<T.Value>> where T.ParentResource: FileResource
}

public extension CoreDependencies {
    class File: FileDependency {
        private var fileSources = WeakAtomicCollection<URL, AnyObject>()
        private var elementSources = WeakAtomicCollection<String, AnyObject>()
        
        public init() {}
        
        public func fileResource<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : FileResource {
            defer { fileSources.prune() }
            return fileSources[resource.fileURL] {
                FileResourceSource(resource: resource)
            }
        }
        
        public func fileResourceElement<T: ResourceElement>(_ resource: T) -> Source<Persistable<T.Value>> where T.ParentResource: FileResource {
            let fileSource: Source<Persistable<T.ParentResource.Value>> = fileSources[resource.parentResource.fileURL] {
                FileResourceSource(resource: resource.parentResource)
            }
            defer {
                fileSources.prune()
                elementSources.prune()
            }
            return elementSources[resource.elementIdentifier] {
                FileResourceElementSource(resource: resource, fileSource: fileSource)
            }
        }
    }
    
    private final class FileResourceSource<Resource: FileResource>: Source<Persistable<Resource.Value>>, ActionSource {
        
        struct Actions: ActionMethods {
            var set = ActionMethod(FileResourceSource.set)
            var clear = ActionMethod(FileResourceSource.clear)
        }
        
        struct MutableProperties {
            var expiredWorkItem: DispatchWorkItem?
            var saveData: Data?
            var saveDate: Date = Date()
        }

        private let resource: Resource
        private let state: MutableState<MutableProperties>
        
        init(resource: Resource) {
            self.resource = resource
            state = MutableState<MutableProperties>(mutableProperties: .init()) { state in .notFound(.init(error: nil, set: state.action(\.set))) }
            super.init(state)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: resource.fileURL.path)
                let persistedDate = attributes[FileAttributeKey.modificationDate] as? Date ?? .distantPast
                let data = try resource.decode(Data(contentsOf: resource.fileURL))
                var isExpired = { false }
                if let expireAfter = resource.expireFileAfter {
                    isExpired = { expireAfter < Date.timeIntervalSinceReferenceDate - persistedDate.timeIntervalSinceReferenceDate }
                    // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
                    let refreshTime = (persistedDate.timeIntervalSinceReferenceDate + expireAfter) - Date.timeIntervalSinceReferenceDate
                    if refreshTime > 0 {
                        let workItem = DispatchWorkItem {
                            [weak self] in
                            guard let self = self else { return }
                            if case .found(let found) = self.model, found.isExpired {
                                self.state.setModel(.found(found))
                            }
                        }
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + refreshTime, execute: workItem)
                        state.expiredWorkItem = workItem
                    }
                }
                state.setModel(.found(.init(value: data, isExpired: isExpired, set: state.action(\.set), clear: state.action(\.clear))))
            } catch {
                state.setModel(.notFound(.init(error: error, set: state.action(\.set))))
            }
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.willTerminateNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.didEnterBackgroundNotification, object: nil)
        }

        @objc private func save() {
            guard let data = state.saveData else {
                try? FileManager.default.removeItem(at: resource.fileURL)
                return
            }
            do {
                try FileManager.default.createDirectory(at: self.resource.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try data.write(to: self.resource.fileURL)
                var attributes = try FileManager.default.attributesOfItem(atPath: self.resource.fileURL.path)
                attributes[FileAttributeKey.modificationDate] = state.saveDate
                try? FileManager.default.setAttributes(attributes, ofItemAtPath: self.resource.fileURL.path)
            } catch {
                self.state.setModel(.notFound(.init(error: error, set: self.state.action(\.set))))
            }
        }

        private func set(value: Resource.Value) {
            state.expiredWorkItem?.cancel()
            let saveDate = Date()
            state.saveDate = saveDate
            var isExpired = { false }
            if let expireAfter = self.resource.expireFileAfter {
                isExpired = {
                    expireAfter < Date.timeIntervalSinceReferenceDate - saveDate.timeIntervalSinceReferenceDate
                }
                // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if case .found(let found) = self.model, found.isExpired {
                        self.state.setModel(.found(found))
                    }
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + expireAfter, execute: workItem)
                self.state.expiredWorkItem = workItem
            }
            state.setModel(.found(.init(value: value, isExpired: isExpired, set: state.action(\.set), clear: state.action(\.clear))))
            do {
                let data = try self.resource.encode(value)
                state.saveData = data
            } catch {
                state.saveData = nil
                self.state.setModel(.notFound(.init(error: error, set: self.state.action(\.set))))
            }
        }

        private func clear() {
            state.expiredWorkItem?.cancel()
            state.saveData = nil
            state.setModel(.notFound(.init(set: state.action(\.set))))
        }

        deinit {
            save()
        }
    }

    private final class FileResourceElementSource<Resource: ResourceElement>: Source<Persistable<Resource.Value>>, ActionSource where Resource.ParentResource: FileResource {

        struct Actions: ActionMethods {
            var set = ActionMethod(FileResourceElementSource.set)
            var clear = ActionMethod(FileResourceElementSource.clear)
        }

        private let resource: Resource
        private let state: State
        private let fileSource: Source<Persistable<Resource.ParentResource.Value>>

        init(resource: Resource, fileSource: Source<Persistable<Resource.ParentResource.Value>>) {
            self.resource = resource
            self.fileSource = fileSource
            state = .init { state in .notFound(.init(set: state.action(\.set))) }
            super.init(state)
            switch fileSource.model {
            case .found(let found):
                do {
                    guard let value = try resource.getElement(from: found.value) else {
                        state.setModel(.notFound(.init(set: state.action(\.set))))
                        return
                    }
                    state.setModel(.found(.init(value: value, isExpired: { found.isExpired }, set: state.action(\.set), clear: state.action(\.clear))))
                } catch {
                    state.setModel(.notFound(.init(error: error, set: state.action(\.set))))
                }
            case .notFound:
                state.setModel(.notFound(.init(set: state.action(\.set))))
            }
        }

        private func set(value: Resource.Value) {
            let fileValue: Resource.ParentResource.Value?
            switch fileSource.model {
            case .notFound:
                fileValue = nil
            case .found(let found):
                fileValue = found.value
            }

            let closure = resource.set(element: value)

            do {
                let parentValue = try closure(fileValue)
                let fileSource = fileSource
                state.setModel(.found(.init(value: value, isExpired: { fileSource.model.found?.isExpired == true }, set: state.action(\.set), clear: state.action(\.clear))))
                try? fileSource.model.set(parentValue)
            } catch {
                state.setModel(.notFound(.init(error: error, set: state.action(\.set))))
            }
        }

        private func clear() {
            let fileValue: Resource.ParentResource.Value?
            switch fileSource.model {
            case .notFound:
                fileValue = nil
            case .found(let found):
                fileValue = found.value
            }

            let closure = resource.set(element: nil)

            do {
                let value = try closure(fileValue)
                state.setModel(.notFound(.init(set: state.action(\.set))))
                try? fileSource.model.set(value)
            } catch {
                state.setModel(.notFound(.init(error: error, set: state.action(\.set))))
            }
        }
    }
}

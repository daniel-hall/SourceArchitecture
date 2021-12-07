//
//  UserDefaultsDependency.swift
///  SourceArchitecture
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


/// Expresses dependency on a small user-specific value persistence mechanism (e.g. the platform Preferences or UserDefaults) that can return an updating Source of a Persistable<Value> for a specified UserDefaultsResource
public protocol UserDefaultsDependency {
    func userDefaultsResource<T: UserDefaultsResource>(_ resource: T) -> Source<Persistable<T.Value>>
    func userDefaultsResourceElement<T: ResourceElement>(_ resource: T) -> Source<Persistable<T.Value>> where T.ParentResource: UserDefaultsResource
}

public extension CoreDependencies {
    class UserDefaults: UserDefaultsDependency {
        private let sources = WeakAtomicCollection<String, AnyObject>()
        private var elementSources = WeakAtomicCollection<String, AnyObject>()
        
        public init() {}
        
        public func userDefaultsResource<T>(_ resource: T) -> Source<Persistable<T.Value>> where T : UserDefaultsResource {
            defer { sources.prune() }
            return sources[resource.userDefaultsIdentifier] {
                UserDefaultsResourceSource(resource: resource)
            }
        }
        
        public func userDefaultsResourceElement<T: ResourceElement>(_ resource: T) -> Source<Persistable<T.Value>> where T.ParentResource: UserDefaultsResource {
            let userDefaultsSource: Source<Persistable<T.ParentResource.Value>> = sources[resource.parentResource.userDefaultsIdentifier] {
                UserDefaultsResourceSource(resource: resource.parentResource)
            }
            defer {
                sources.prune()
                elementSources.prune()
            }
            return elementSources[resource.elementIdentifier] {
                UserDefaultsResourceElementSource(resource: resource, userDefaultsSource: userDefaultsSource)
            }
        }
    }
    
    private struct UserDefaultsRecord: Codable {
        let persistedDate: Date
        let data: Data
    }
    
    private final class UserDefaultsResourceSource<Resource: UserDefaultsResource>: Source<Persistable<Resource.Value>>, ActionSource {
        
        struct Actions: ActionMethods {
            var set = ActionMethod(UserDefaultsResourceSource.set)
            var clear = ActionMethod(UserDefaultsResourceSource.clear)
        }
        
        struct MutableProperties {
            var expiredWorkItem: DispatchWorkItem?
            var saveData: Data?
        }

        private let resource: Resource
        private let state: MutableState<MutableProperties>
        
        init(resource: Resource) {
            self.resource = resource
            state = MutableState<MutableProperties>(mutableProperties: .init()) { state in .notFound(.init(error: nil, set: state.set)) }
            super.init(state)
            if let data = Foundation.UserDefaults.standard.data(forKey: resource.userDefaultsIdentifier) {
                do {
                    let record = try JSONDecoder().decode(UserDefaultsRecord.self, from: data)
                    var isExpired = { false }
                    if let expireAfter = resource.expireUserDefaultsAfter {
                        isExpired = { expireAfter < Date.timeIntervalSinceReferenceDate - record.persistedDate.timeIntervalSinceReferenceDate }
                        // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
                        let refreshTime = (record.persistedDate.timeIntervalSinceReferenceDate + expireAfter) - Date.timeIntervalSinceReferenceDate
                        if refreshTime > 0 {
                            let workItem = DispatchWorkItem { [weak self] in
                                guard let self = self else { return }
                                if case .found(let found) = self.model, found.isExpired {
                                    self.state.setModel(.found(found))
                                }
                            }
                            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + refreshTime, execute: workItem)
                            state.expiredWorkItem = workItem
                        }
                    }
                    let value = try resource.decode(record.data)
                    state.setModel(.found(.init(value: value, isExpired: isExpired, set: state.set, clear: state.clear)))
                } catch {
                    state.setModel(.notFound(.init(error: error, set: state.set)))
                }
            } else {
                state.setModel(.notFound(.init(set: state.set)))
            }
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.willTerminateNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(save), name: UIApplication.willResignActiveNotification, object: nil)
        }

        @objc private func save() {
            guard let data = state.saveData else {
                return
            }
            Foundation.UserDefaults.standard.set(data, forKey: resource.userDefaultsIdentifier)
            state.saveData = nil
        }

        private func set(value: Resource.Value) {
            state.expiredWorkItem?.cancel()
            do {
                let record = try UserDefaultsRecord(persistedDate: Date(), data: resource.encode(value))
                let data = try JSONEncoder().encode(record)
                state.saveData = data
                var isExpired = { false }
                if let expireAfter = resource.expireUserDefaultsAfter {
                    isExpired = {
                        expireAfter < Date.timeIntervalSinceReferenceDate - record.persistedDate.timeIntervalSinceReferenceDate
                    }
                    // If an expiration date is set, schedule an update at that time so that downstream subscribers are updated
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        if case .found(let found) = self.model, found.isExpired {
                            self.state.setModel(.found(found))
                        }
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + expireAfter, execute: workItem)
                    state.expiredWorkItem = workItem
                }
                state.setModel(.found(.init(value: value, isExpired: isExpired, set: state.set, clear: state.clear)))
            } catch {
                state.setModel(.notFound(.init(error: error, set: state.set)))
            }
        }
        
        private func clear() {
            state.expiredWorkItem?.cancel()
            state.saveData = nil
            state.setModel(.notFound(.init(set: state.set)))
            Foundation.UserDefaults.standard.removeObject(forKey: resource.userDefaultsIdentifier)
        }

        deinit {
            save()
        }
    }
    
    
    private final class UserDefaultsResourceElementSource<Resource: ResourceElement>: Source<Persistable<Resource.Value>>, ActionSource where Resource.ParentResource: UserDefaultsResource {
        
        struct Actions: ActionMethods {
            var set = ActionMethod(UserDefaultsResourceElementSource.set)
            var clear = ActionMethod(UserDefaultsResourceElementSource.clear)
        }
        
        private let resource: Resource
        private let state: State
        private let userDefaultsSource: Source<Persistable<Resource.ParentResource.Value>>
        
        init(resource: Resource, userDefaultsSource: Source<Persistable<Resource.ParentResource.Value>>) {
            self.resource = resource
            self.userDefaultsSource = userDefaultsSource
            state = .init { state in .notFound(.init(set: state.set)) }
            super.init(state)
            switch userDefaultsSource.model {
            case .found(let found):
                do {
                    guard let value = try resource.getElement(from: found.value) else {
                        state.setModel(.notFound(.init(set: state.set)))
                        return
                    }
                    state.setModel(.found(.init(value: value, isExpired: { found.isExpired }, set: state.set, clear: state.clear)))
                } catch {
                    state.setModel(.notFound(.init(error: error, set: state.set)))
                }
            case .notFound:
                state.setModel(.notFound(.init(set: state.set)))
            }
        }
        
        private func set(value: Resource.Value) {
            let userDefaultsValue: Resource.ParentResource.Value?
            switch userDefaultsSource.model {
            case .notFound:
                userDefaultsValue = nil
            case .found(let found):
                userDefaultsValue = found.value
            }
            
            let closure = resource.set(element: value)
            
            do {
                let parentValue = try closure(userDefaultsValue)
                let userDefaultsSource = userDefaultsSource
                state.setModel(.found(.init(value: value, isExpired: { userDefaultsSource.model.found?.isExpired == true }, set: state.set, clear: state.clear)))
                try? userDefaultsSource.model.set(parentValue)
            } catch {
                state.setModel(.notFound(.init(error: error, set: state.set)))
            }
        }
        
        private func clear() {
            let userDefaultsValue: Resource.ParentResource.Value?
            switch userDefaultsSource.model {
            case .notFound:
                userDefaultsValue = nil
            case .found(let found):
                userDefaultsValue = found.value
            }
            
            let closure = resource.set(element: nil)
            
            do {
                let value = try closure(userDefaultsValue)
                state.setModel(.notFound(.init(set: state.set)))
                try? userDefaultsSource.model.set(value)
            } catch {
                state.setModel(.notFound(.init(set: state.set)))
            }
        }
    }
}

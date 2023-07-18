//
//  ToDoListSource.swift
//  ToDoList
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
import Combine


/// The Model which represents the current state and available API for a ToDoList
public struct ToDoList: Codable, Versioned {

    private enum CodingKeys: String, CodingKey {
        case id
        case items
        case version
        case add
    }

    private let id: String
    public let items: [AnySource<ToDoItemView.Model>]
    public let version: Date
    public let add: Action<Void>
    fileprivate let mutableItemSources: [AnySource<Mutable<ToDoItem>>]

    fileprivate init(items: [AnySource<ToDoItemView.Model>] = [], mutableItemSources: [AnySource<Mutable<ToDoItem>>] = [], add: Action<Void>, version: Date = .now) {
        self.id = "1"
        self.items = items
        self.version = .now
        self.add = add
        self.mutableItemSources = mutableItemSources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.version = try container.decode(Date.self, forKey: .version)
        self.add = try container.decode(Action<Void>.self, forKey: .add)
        let decodedItems = try container.decode([ToDoItem].self, forKey: .items)
        self.mutableItemSources = decodedItems.map { MutableSource($0).eraseToAnySource() }
        self.items = mutableItemSources.map { ToDoItemViewSource($0).eraseToAnySource() }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mutableItemSources.map { $0.state.value }, forKey: .items)
        try container.encode(add, forKey: .add)
        try container.encode(version, forKey: .version)
    }
}

public struct ToDoItem: Codable, Equatable, Identifiable {
    public var id: String
    public var description: String
    public var dateCompleted: Date?
    public var isDeleted: Bool
}

public protocol PersistableToDoListDependency {
    var persistedToDoList: AnySource<Persistable<ToDoList>> { get }
}

public final class ToDoListSource: Source<ToDoList> {

    public typealias Dependencies = PersistableToDoListDependency

    @ActionFromMethod(add) private var addAction

    @Sourced private var persistedList: Persistable<ToDoList>

    public lazy var initialState = ToDoList(add: addAction)
    public var subscriptions: [String: AnyCancellable] = [:]

    public init(dependencies: Dependencies) {
        _persistedList = .init(from: dependencies.persistedToDoList, updating: ToDoListSource.update)
    }

    public func onStart() {
        update(new: persistedList)
    }

    /// Whenever a change to our persisted List is detected, deserialize all the saved items and update our Model to reflect the current state of the List and all ToDoItems. Note that in this sample app, the persisted List can be changed either locally or by newer versions being retrieved from the Network.
    private func update(new: Persistable<ToDoList>) {
        switch new {
        case .notFound:
            state = .init(add: addAction)
        case .found(let found):
            var updatedSources = state.mutableItemSources.filter{ existing in
                found.value.items.contains{  $0.id == existing.id }
            }
            var updatedRenderables = state.items.filter { existing in
                found.value.items.contains { $0.id == existing.id }
            }
            updatedSources.forEach { subscriptions.removeValue(forKey: $0.id) }
            found.value.mutableItemSources.forEach { new in
                if let existing = updatedSources.first(where: { $0.id == new.id }) {
                    existing.state.set(new.state.value)
                } else {
                    updatedSources += [new]
                    updatedRenderables += [found.value.items.first{ $0.id == new.id }!]
                }
            }
            updatedSources.forEach {
                subscriptions[$0.id] = $0.eraseToAnyPublisher().sink { [weak self] in
                    self?.itemUpdated($0)
                }
            }
            state = .init(items: updatedRenderables, mutableItemSources: updatedSources, add: state.add)
        }
    }

    /// When a ToDoItem is updated (e.g. the user marks it as completed or updated the description), serialize our ToDoList with all ToDoItems to persistence to save it (and update the version to the current timestamp)
    private func itemUpdated(_ item: Mutable<ToDoItem>) {
        let items = state.items.filter { item in
            state.mutableItemSources.first { $0.id == item.id }?.state.value.isDeleted == false
        }
        let save = ToDoList(items: items, mutableItemSources: state.mutableItemSources.filter { !$0.state.value.isDeleted }, add: state.add, version: .now)
        persistedList.set(save)
    }

    /// When a new ToDoItem should be added, create an empty new SavedToDoItem and write it to our persistence
    private func add() {
        // Create a new SavedToDoList consisting of any existing items plus a new SavedToDoItem
        let newSource = MutableSource(ToDoItem(id: UUID().uuidString, description: "", dateCompleted: nil, isDeleted: false)).eraseToAnySource()
        let updatedList = ToDoList(items: state.items + [ToDoItemViewSource(newSource).eraseToAnySource()], mutableItemSources: state.mutableItemSources + [newSource], add: state.add, version: .now)
        // Persist the new list
        persistedList.set(updatedList)
    }
}

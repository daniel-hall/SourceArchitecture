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


/// The Model which represents the current state and available API for a ToDoList
public struct ToDoList: Codable, Versioned {

    private enum CodingKeys: String, CodingKey {
        case id
        case items
        case version
        case add
    }

    private let id: String
    public let items: [Source<ToDoItemView.Model>]
    public let version: Date
    public let add: Action<Void>
    fileprivate let mutableItemSources: [Source<Mutable<ToDoItem>>]

    fileprivate init(items: [Source<ToDoItemView.Model>] = [], mutableItemSources: [Source<Mutable<ToDoItem>>] = [], add: Action<Void>, version: Date = .now) {
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
        self.mutableItemSources = decodedItems.map { MutableSource($0).eraseToSource() }
        self.items = mutableItemSources.map { ToDoItemViewSource($0).eraseToSource() }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mutableItemSources.map { $0.model.value }, forKey: .items)
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
    var persistedToDoList: Source<Persistable<ToDoList>> { get }
}

public final class ToDoListSource: SourceOf<ToDoList> {

    public typealias Dependencies = PersistableToDoListDependency

    @Action(ToDoListSource.add) private var addAction

    public lazy var initialModel = ToDoList(add: addAction)
    private var persistedList: Source<Persistable<ToDoList>>

    public init(dependencies: Dependencies) {
        self.persistedList = dependencies.persistedToDoList
        super.init()
        persistedList.subscribe(self, method: ToDoListSource.update)
    }

    /// Whenever a change to our persisted List is detected, deserialize all the saved items and update our Model to reflect the current state of the List and all ToDoItems. Note that in this sample app, the persisted List can be changed either locally or by newer versions being retrieved from the Network.
    private func update(new: Persistable<ToDoList>) {
        switch new {
        case .notFound:
            model = .init(add: addAction)
        case .found(let found):
            var updatedSources = model.mutableItemSources.filter{ existing in
                found.items.contains{  $0.id == existing.id }
            }
            var updatedRenderables = model.items.filter { existing in
                found.items.contains { $0.id == existing.id }
            }
            updatedSources.forEach { $0.unsubscribe(self) }
            found.mutableItemSources.forEach { new in
                if let existing = updatedSources.first(where: { $0.id == new.id }) {
                    existing.model.set(new.model.value)
                } else {
                    updatedSources += [new]
                    updatedRenderables += [found.items.first{ $0.id == new.id }!]
                }
            }
            updatedSources.forEach { $0.subscribe(self, method: ToDoListSource.itemUpdated, sendInitialModel: false) }
            model = .init(items: updatedRenderables, mutableItemSources: updatedSources, add: model.add)
        }
    }

    /// When a ToDoItem is updated (e.g. the user marks it as completed or updated the description), serialize our ToDoList with all ToDoItems to persistence to save it (and update the version to the current timestamp)
    private func itemUpdated(_ item: Mutable<ToDoItem>) {
        let items = model.items.filter { item in
            model.mutableItemSources.first { $0.id == item.id }?.model.isDeleted == false
        }
        let save = ToDoList(items: items, mutableItemSources: model.mutableItemSources.filter { !$0.model.isDeleted }, add: model.add, version: .now)
        persistedList.model.set(save)
    }

    /// When a new ToDoItem should be added, create an empty new SavedToDoItem and write it to our persistence
    private func add() {
        // Create a new SavedToDoList consisting of any existing items plus a new SavedToDoItem
        let newSource = MutableSource(ToDoItem(id: UUID().uuidString, description: "", dateCompleted: nil, isDeleted: false)).eraseToSource()
        let updatedList = ToDoList(items: model.items + [ToDoItemViewSource(newSource).eraseToSource()], mutableItemSources: model.mutableItemSources + [newSource], add: model.add, version: .now)
        // Persist the new list
        persistedList.model.set(updatedList)
    }
}

//
//  ToDoListSource.swift
//  SyncedToDoListApp
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

import SourceArchitecture
import Foundation
import Combine
import OrderedCollections


/// The Model which represents the current state and available API for a ToDoList
struct ToDoList {
    var items: [ModelState<ToDoItem>]
    var add: Action<Void>
}

/// A data-only Codable struct used to write a ToDoList to persistence (e.g. a File). In order to work with NetworkSyncedPersistedSource it also must conform to the `Versioned` protocol so the most recent version (local persistence or network) can be used.
struct CodableToDoList: Codable, Versioned {
    var id = "1"
    var items: [CodableToDoItem]
    var version: Date
}

protocol PersistableToDoListDependency {
    var persistedToDoList: Source<Persistable<CodableToDoList>> { get }
}

final class ToDoListSource: CustomSource {
    typealias Dependencies = PersistableToDoListDependency

    /// Actions this Source can provide, and which methods they map to
    class Actions: ActionMethods {
        var add = ActionMethod(ToDoListSource.add)
    }
    /// Properties used by this source which may be read / written from multiple threads
    class Threadsafe: ThreadsafeProperties {
        var mutableToDoItemSources = [HashableMutableToDoItemSource]()
        var toDoItemSources = [Source<ToDoItem>]()
    }

    struct HashableMutableToDoItemSource: Hashable {
        static func == (lhs: HashableMutableToDoItemSource, rhs: HashableMutableToDoItemSource) -> Bool {
            lhs.source.model.value.id == rhs.source.model.value.id
        }
        let source: Source<Mutable<CodableToDoItem>>
        func hash(into hasher: inout Hasher) {
            hasher.combine(source.model.value.id)
        }
    }

    lazy var defaultModel = ToDoList(items: [], add: actions.add)
    private var persistedList: Source<Persistable<CodableToDoList>>

    init(dependencies: Dependencies) {
        self.persistedList = dependencies.persistedToDoList
        super.init()
        persistedList.subscribe(self, method: ToDoListSource.update)
    }

    /// Whenever a change to our persisted List is detected, deserialize all the saved items and update our Model to reflect the current state of the List and all ToDoItems. Note that in this sample app, the persisted List can be changed either locally or by newer versions being retrieved from the Network.
    private func update(new: Persistable<CodableToDoList>) {
        switch new {
        case .notFound:
            model = .init(items: [], add: actions.add)
        case .found(let found):
            // Unsubscribe from the Sources while we are making updates so we don't trigger an update loop
            threadsafe.toDoItemSources.forEach { $0.unsubscribe(self) }
            // Create Sources for all ToDoItems found in persistence
            let persistedItems = OrderedSet(found.value.items.map {
                HashableMutableToDoItemSource(source: MutableSource($0).eraseToSource().filteringDuplicates())
            })
            // Remove any deleted items and add any new items found in persistence to our mutable sources
            threadsafe.mutableToDoItemSources = Array(OrderedSet( threadsafe.mutableToDoItemSources)
                .intersection(persistedItems)
                .union(persistedItems)
                .enumerated().map {
                    $0.element.source.model.set(persistedItems[$0.offset].source.model.value)
                    return $0.element
                })
            // Make sure there is a final mapped ToDoItemSource for each mutable source we created above
            threadsafe.toDoItemSources = threadsafe.mutableToDoItemSources.map { item in
                // If a ToDoItem source already exists for an ID, use the existing one, otherwise create a new one and subscribe to any changes that get made to it
                return threadsafe.toDoItemSources.first { $0.model.id == item.source.model.id } ?? ToDoItemSource(item.source.map{ $0.value }).eraseToSource()
            }
            // Update our models items with any new ToDoItem sources that were created and resubscribe to changes
            model.items = threadsafe.toDoItemSources.map {
                $0.subscribe(self, method: ToDoListSource.itemUpdated, shouldSendInitialValue: false)
                return $0.$model
            }
        }
    }

    /// When a ToDoItem is updated (e.g. the user marks it as completed or updated the description), serialize our ToDoList with all ToDoItems to persistence to save it (and update the version to the current timestamp)
    private func itemUpdated(item: ToDoItem) {
        let currentItems = model.items.filter { !$0.model.isDeleted }
        // Map all the current ToDoItems to an array of serialized SavedToDoItems that will be written to persistence
        let items = currentItems.map { CodableToDoItem(id: $0.model.id, description: $0.model.description, dateCompleted: $0.model.dateCompleted) }
        persistedList.model.set(.init(items: items, version: .now))
    }

    /// When a new ToDoItem should be added, create an empty new SavedToDoItem and write it to our persistence
    private func add() {
        // Create a new SavedToDoList consisting of any existing items plus a new SavedToDoItem
        let updatedList = CodableToDoList(items: (persistedList.model.found?.value.items ?? []) + [.init(id: UUID().uuidString, description: "", dateCompleted: nil)], version: .now)
        // Persist the new list
        persistedList.model.set(updatedList)
    }
}

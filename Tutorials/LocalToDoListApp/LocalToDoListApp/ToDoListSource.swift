//
//  ToDoListSource.swift
//  LocalToDoListApp
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

import SourceArchitecture
import Foundation
import Combine


struct ToDoItem: Equatable, Identifiable {
    let id: String
    let description: String
    let dateCompleted: Date?
    let setCompleted: Action<Bool>
    let setDescription: Action<String>
    let delete: Action<Void>
}

struct ToDoList {
    let name: String
    let items: [Source<ToDoItem>]
    let add: Action<Void>
}

final class ToDoListSource: Source<ToDoList>, ActionSource {
    struct Actions: ActionMethods {
        var add = ActionMethod(ToDoListSource.add)
    }
    private let state: State
    private let persisted: Source<Persistable<[SavedToDoItem]>>
    private var subscriptions = Set<AnyCancellable>()

    init(dependencies: FileDependency) {
        self.persisted = dependencies.fileResource(ToDoListResource())
        state = State(model: ToDoList(name: "To Do", items: [], add: .noOp))
        super.init(state)
        persisted.subscribe(self, method: ToDoListSource.update)
        ToDoItemSource.itemDeletedPublisher.sink { [weak self] item in
            guard let self = self else { return }
            let items = self.model.items.asSavedItems.filter { $0.id != item.id }
            try? self.persisted.model.set(items)
        }.store(in: &subscriptions)
        ToDoItemSource.itemChangedPublisher.sink { [weak self] item in
            guard let self = self else { return }
            let items = self.model.items.asSavedItems.map { $0.id == item.id ? SavedToDoItem(id: item.id, description: item.description, dateCompleted: item.dateCompleted) : $0 }
            try? self.persisted.model.set(items)
        }.store(in: &subscriptions)
    }

    private func update() {
        switch persisted.model {
        case .notFound: state.setModel(ToDoList(name: "To Do", items: [], add: state.add))
        case .found(let found): state.setModel(ToDoList(name: "To Do", items: found.value.map { ToDoItemSource($0) }, add: state.add))
        }
    }

    private func add() {
        try? persisted.model.set(model.items.asSavedItems + [SavedToDoItem(id: UUID().uuidString, description: "", dateCompleted: nil)])
    }
}

final class ToDoItemSource: Source<ToDoItem>, ActionSource {
    static var itemDeletedPublisher = PassthroughSubject<ToDoItem, Never>()
    static var itemChangedPublisher = PassthroughSubject<ToDoItem, Never>()
    struct Actions: ActionMethods {
        var setDescription = ActionMethod(ToDoItemSource.setDescription)
        var delete = ActionMethod(ToDoItemSource.delete)
        var setCompleted = ActionMethod(ToDoItemSource.setCompleted)
    }
    private let state: State

    fileprivate init(_ item: SavedToDoItem) {
        state = State(model: { state in ToDoItem(id: item.id, description: item.description, dateCompleted: item.dateCompleted, setCompleted: state.setCompleted, setDescription: state.setDescription, delete: state.delete) })
        super.init(state)
    }

    private func setDescription(_ description: String) {
        state.setModel(ToDoItem(id: model.id, description: description, dateCompleted: model.dateCompleted, setCompleted: state.setCompleted, setDescription: state.setDescription, delete: state.delete))
        Self.itemChangedPublisher.send(model)
    }

    private func delete() {
        Self.itemDeletedPublisher.send(model)
    }

    private func setCompleted(_ isCompleted: Bool) {
        let dateCompleted: Date? = isCompleted ? .now : nil
        state.setModel(ToDoItem(id: model.id, description: model.description, dateCompleted: dateCompleted, setCompleted: state.setCompleted, setDescription: state.setDescription, delete: state.delete))
        Self.itemChangedPublisher.send(model)
    }
}

fileprivate extension Array where Element == Source<ToDoItem> {
    var asSavedItems: [SavedToDoItem] {
        map { SavedToDoItem(id: $0.model.id, description: $0.model.description, dateCompleted: $0.model.dateCompleted) }
    }
}

private struct SavedToDoItem: Codable {
    let id: String
    let description: String
    let dateCompleted: Date?
}

private struct ToDoListResource: FileResource {
    typealias Value = [SavedToDoItem]
    var fileDirectory: FileManager.SearchPathDirectory { .documentDirectory }
    var filePath: String { "ToDoList" }
}

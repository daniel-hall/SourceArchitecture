//
//  ToDoListItemSource.swift
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


struct ToDoItem: Equatable, Identifiable {
    var id: String
    var description: String
    var dateCompleted: Date?
    var isDeleted: Bool
    var setCompleted: Action<Bool>
    var setDescription: Action<String>
    var delete: Action<Void>
}

struct CodableToDoItem: Codable, Equatable {
    var id: String
    var description: String
    var dateCompleted: Date?
}

final class ToDoItemSource: CustomSource {
    class Actions: ActionMethods {
        var setDescription = ActionMethod(ToDoItemSource.setDescription)
        var delete = ActionMethod(ToDoItemSource.delete)
        var setCompleted = ActionMethod(ToDoItemSource.setCompleted)
    }
    lazy var defaultModel = ToDoItem(id: saved.model.id, description: saved.model.description, dateCompleted: saved.model.dateCompleted, isDeleted: false, setCompleted: actions.setCompleted, setDescription: actions.setDescription, delete: actions.delete)

    private let saved: Source<CodableToDoItem>

    init(_ saved: Source<CodableToDoItem>) {
        self.saved = saved.filteringDuplicates()
        super.init()
        saved.subscribe(self, method: ToDoItemSource.saveUpdated, shouldSendInitialValue: false)
    }

    private func saveUpdated(value: CodableToDoItem) {
        model = ToDoItem(id: value.id, description: value.description, dateCompleted: value.dateCompleted, isDeleted: false, setCompleted: model.setCompleted, setDescription: model.setDescription, delete: model.delete)
    }

    private func setDescription(_ description: String) {
        model.description = description
    }

    private func delete() {
        model.isDeleted = true
    }

    private func setCompleted(_ isCompleted: Bool) {
        let dateCompleted: Date? = isCompleted ? .now : nil
        model.dateCompleted = dateCompleted
    }
}

//
//  ToDoListItemSource.swift
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

import SourceArchitecture
import SwiftUI

internal final class ToDoItemViewSource: SourceOf<ToDoItemView.Model> {
    @Action(delete) private var deleteAction
    @Action(setCompleted) private var setCompletedAction

    internal lazy var initialModel = ToDoItemView.Model(id: saved.model.id,
                                                        description: .init(source: self,
                                                                           keyPath: \.description),
                                                        isCompleted: saved.model.dateCompleted != nil,
                                                        setCompleted: setCompletedAction,
                                                        delete: deleteAction)

    private let saved: Source<Mutable<ToDoItem>>

    private var description: String {
        get {
            saved.model.description
        }
        set {
            setDescription(newValue)
        }
    }

    internal init(_ saved: Source<Mutable<ToDoItem>>) {
        self.saved = saved.filteringDuplicates()
        super.init()
        self.saved.subscribe(self, method: ToDoItemViewSource.saveUpdated, sendInitialModel: false)
    }

    private func saveUpdated(value: Mutable<ToDoItem>) {
        model = .init(id: value.id,
                      description: .init(source: self, keyPath: \.description),
                      isCompleted: value.dateCompleted != nil,
                      setCompleted: setCompletedAction,
                      delete: deleteAction)
    }

    private func setDescription(_ description: String) {
        guard description != saved.model.description else { return }
        saved.model.set(
            .init(id: model.id,
                  description: description.replacingOccurrences(of: "\n", with: ""),
                  dateCompleted: saved.model.dateCompleted,
                  isDeleted: saved.model.isDeleted)
        )
    }

    private func delete() {
        saved.model.set(
            .init(id: model.id,
                  description: model.description,
                  dateCompleted: saved.model.dateCompleted,
                  isDeleted: true)
        )
    }

    private func setCompleted(_ isCompleted: Bool) {
        let dateCompleted: Date? = isCompleted ? .now : nil
        saved.model.set(
            .init(id: model.id,
                  description: model.description,
                  dateCompleted: dateCompleted,
                  isDeleted: saved.model.isDeleted)
        )
    }
}

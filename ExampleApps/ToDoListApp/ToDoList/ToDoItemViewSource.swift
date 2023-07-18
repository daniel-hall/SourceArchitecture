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

internal final class ToDoItemViewSource: Source<ToDoItemView.Model> {
    @ActionFromMethod(delete) private var deleteAction
    @ActionFromMethod(setCompleted) private var setCompletedAction

    internal lazy var initialState = ToDoItemView.Model(id: saved.value.id,
                                                        description: .init(source: self,
                                                                           keyPath: \.description),
                                                        isCompleted: saved.value.dateCompleted != nil,
                                                        setCompleted: setCompletedAction,
                                                        delete: deleteAction)

    @Sourced private var saved: Mutable<ToDoItem>

    private var description: String {
        get {
            saved.value.description
        }
        set {
            setDescription(newValue)
        }
    }

    internal init(_ saved: AnySource<Mutable<ToDoItem>>) {
        _saved = .init(from: saved.filteringDuplicates(), updating: ToDoItemViewSource.saveUpdated)
    }

    private func saveUpdated(value: Mutable<ToDoItem>) {
        state = .init(id: value.id,
                      description: .init(source: self, keyPath: \.description),
                      isCompleted: value.value.dateCompleted != nil,
                      setCompleted: setCompletedAction,
                      delete: deleteAction)
    }

    private func setDescription(_ description: String) {
        guard description != saved.value.description else { return }
        saved.set(
            .init(id: state.id,
                  description: description.replacingOccurrences(of: "\n", with: ""),
                  dateCompleted: saved.value.dateCompleted,
                  isDeleted: saved.value.isDeleted)
        )
    }

    private func delete() {
        saved.set(
            .init(id: state.id,
                  description: state.description,
                  dateCompleted: saved.value.dateCompleted,
                  isDeleted: true)
        )
    }

    private func setCompleted(_ isCompleted: Bool) {
        let dateCompleted: Date? = isCompleted ? .now : nil
        saved.set(
            .init(id: state.id,
                  description: state.description,
                  dateCompleted: dateCompleted,
                  isDeleted: saved.value.isDeleted)
        )
    }
}

//
//  AppDependencies.swift
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

import Foundation
import SourceArchitecture
import ToDoList


/// In order to make the ToDoListApp synced with a backend, the only thing we need to do is pass a `NetworkSyncedPersistableSource` as the dependency instead of just a FilePersistence Source dependency. All the shared ToDoList framework code remains identical!
struct AppDependencies: PersistableToDoListDependency {
    private let filePersistence = FilePersistence()

    var persistedToDoList: Source<Persistable<CodableToDoList>> {
        let fileDescriptor = FilePersistence.Descriptor<CodableToDoList>(directory: .documentDirectory, path: "ToDoList")
        return NetworkSyncedPersistableSource(persisted: filePersistence[fileDescriptor],
                                              // The network GET source for getting the network version of the value
                                              get: API.getToDoList,
                                              // We use a single shared list, no creating new ones on the network
                                              create: { .singleValue(.fetched(.init(value: $0, refresh: .doNothing))) },
                                              // The network PUT source for writing local updates to remote
                                              update: { API.updateToDoList($0) },
                                              // We don't allow deleting the shared list
                                              delete: { .singleValue(.fetched(.init(value: $0, refresh: .doNothing)))}
        ).eraseToSource()
    }
}

let appDependencies = AppDependencies()

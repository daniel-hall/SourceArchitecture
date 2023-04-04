//
//  ToDoListView.swift
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
import SwiftUI


public struct ToDoListView: View, Renderer {

    @Source public var model: ToDoList
    @FocusState private var focus: String?
    @State private var hasNewCell = false
    @State private var refresh = 0
    @State private var scroll = DispatchWorkItem { }

    public init(source: Source<ToDoList>) {
        _model = source
    }

    public var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List(model.items) { item in
                    ToDoItemView(source: item, isNew: item.id == model.items.last?.id ? $hasNewCell : nil, proxy: model.items.count > 5 ? proxy : nil, focus: $focus)
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                item.model.delete()
                            }
                        }
                }
                .id(refresh)
                .animation(.default, value: model.items)
                .onChange(of: focus) {
                    if let focus = $0 {
                        scroll.cancel()
                        scroll = .init {
                            if model.items.contains(where: { $0.id == focus }) {
                                withAnimation(.default) { proxy.scrollTo(focus, anchor: .bottom) }
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: scroll)
                    }
                }
                .navigationTitle("To Do")
                .toolbar {
                    Button {
                        // Don't add more items if we are in the middle of scrolling to the newest one
                        if hasNewCell { return }
                        hasNewCell = true
                        model.add()
                        // All the below code is an unfortunate, janky workaround for the SwiftUI iOS 16 scrollTo() crash bug
                        // See thread here: https://developer.apple.com/forums/thread/712510
                        withAnimation(.default) {
                            proxy.scrollTo(model.items.last?.id ?? "0", anchor: .bottom)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                refresh += 1
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    focus = model.items.last?.id
                                }
                            }
                        }
                    } label: { Image(systemName: "plus").font(.headline) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

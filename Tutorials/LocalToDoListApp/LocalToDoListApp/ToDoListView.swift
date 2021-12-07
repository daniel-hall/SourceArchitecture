//
//  ToDoListView.swift
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

import Foundation
import SourceArchitecture
import SwiftUI


struct ToDoListView: View, Renderer {
    @ObservedObject var source: AnySource<ToDoList>
    @State private var hasNewCell = false
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List(model.items) { source in
                    ToDoItemView(source: source, isNew: source.model.id == model.items.last?.id ? $hasNewCell : nil, proxy: proxy)
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                try? source.model.delete()
                            }
                        }
                }
                .animation(.default, value: model.items)
                .navigationTitle(model.name)
                .toolbar {
                    Button {
                        // Don't add more items if we are in the middle of scrolling to the newest one
                        if hasNewCell { return }
                        hasNewCell = true
                        try? model.add()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.default) { proxy.scrollTo(model.items.last?.id ?? "0", anchor: .bottom) }
                        }
                    } label: { Image(systemName: "plus").font(.headline) }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct ToDoItemView: View, Renderer {
    @FocusState fileprivate var isFocused: Bool
    @ObservedObject var source: AnySource<ToDoItem>
    @State var description: String = ""
    @Binding var isNew: Bool
    let proxy: ScrollViewProxy

    init(source: AnySource<ToDoItem>, isNew: Binding<Bool>?, proxy: ScrollViewProxy) {
        self.source = source
        self.proxy = proxy
        _isNew = isNew ?? .init(get: { false }, set: { _ in })
        _description = .init(initialValue: source.model.description)
    }

    var body: some View {
        HStack {
            Button {
                let isAlreadyCompleted = model.dateCompleted != nil
                try? model.setCompleted(!isAlreadyCompleted)
            } label: {
                Image(systemName: model.dateCompleted == nil ? "square" : "checkmark.square")
            }
            ZStack {
                // — Workaround to make SwiftUI dynamically size the cell to match the TextEditor contents
                Text(description.isEmpty ? " " : description).strikethrough(model.dateCompleted != nil, color: .gray).frame(maxWidth: .infinity, alignment: .leading).padding(.init(top: 9, leading: 5, bottom: 8, trailing: 5)).foregroundColor(.white)
                // —
                TextEditor(text: $description).frame(alignment: .center).alignmentGuide(VerticalAlignment.center) { $0.height * 0.475 }.focused($isFocused)
            }
        }.foregroundColor(model.dateCompleted == nil ? .black : .gray)
            .onChange(of: description) {
                if $0.last == "\n" {
                    description = String($0.dropLast())
                    isFocused = false
                    return
                }
                try? model.setDescription($0)
                withAnimation(.default) { proxy.scrollTo(model.id, anchor: .bottom) }
            }
            .onChange(of: model.dateCompleted) {
                if $0 != nil { isFocused = false }
            }
            .onChange(of: $isFocused.wrappedValue) {
                if $0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.default) { proxy.scrollTo(model.id, anchor: .bottom) }
                    }
                }
            }
            .onAppear {
                if isNew {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isNew = false
                        isFocused = true
                    }
                }
            }
    }
}

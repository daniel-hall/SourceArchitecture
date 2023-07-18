//
//  ToDoItemView.swift
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


public extension ToDoItemView {

    struct Model: Identifiable, Equatable {
        public var id: String
        @Binding public var description: String
        public var isCompleted: Bool
        public var setCompleted: Action<Bool>
        public var delete: Action<Void>
    }
}

public struct ToDoItemView: View, Renderer {

    @FocusState<String?>.Binding fileprivate var focus: String?
    @Sourced public var model: Model
    @Binding var isNew: Bool
    @State var scroll = DispatchWorkItem { }
    
    let proxy: ScrollViewProxy?

    var descriptionBinding: Binding<String> {
        model.$description.onChange {
            if $0.contains("\n") {
                focus = nil
                return
            }
            scroll.cancel()
            scroll = .init { withAnimation(.default) { proxy?.scrollTo(model.id, anchor: .bottom) } }
            DispatchQueue.main.async(execute: scroll)
        }
    }

    init(source: AnySource<Model>, isNew: Binding<Bool>?, proxy: ScrollViewProxy?, focus: FocusState<String?>.Binding) {
        self.proxy = proxy
        _model = .init(from: source)
        _focus = focus
        _isNew = isNew ?? .init(get: { false }, set: { _ in })
    }

    public var body: some View {
        HStack {
            Button {
                model.setCompleted(!model.isCompleted)
            } label: {
                Image(systemName: model.isCompleted ? "checkmark.square" : "square")
            }
            if #available(iOS 16.0, *) {
                TextField("", text: descriptionBinding, axis: .vertical)
                    .lineLimit(5)
                    .strikethrough(model.isCompleted, color: .gray)
                    .padding(5)
                    .focused($focus, equals: model.id)
            } else {
                ZStack {
                    // — Workaround to make SwiftUI dynamically size the cell to match the TextEditor contents
                    Text(model.description)
                        .strikethrough(model.isCompleted, color: .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.init(top: 9, leading: 5, bottom: 8, trailing: 5))
                        .foregroundColor(.white)
                    // —
                    TextEditor(text: descriptionBinding)
                        .frame(alignment: .center)
                        .alignmentGuide(VerticalAlignment.center){ $0.height * 0.475 }
                        .focused($focus, equals: model.id)
                }
            }
        }
        .foregroundColor(model.isCompleted ? .gray : .black)
        .onChange(of: model.isCompleted) {
            if $0 { focus = nil }
        }
        .onAppear {
            if isNew {
                focus = model.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isNew = false
                }
            }
        }
    }
}

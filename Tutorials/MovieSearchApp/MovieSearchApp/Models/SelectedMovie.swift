//
//  SelectedMovie.swift
//  MovieSearchApp
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

/// A Source that keeps track of the current selected movie ID, allows a new selected ID to be set, and informs all subscribers of changes whenever the selected ID changes.  Because different other Source compose an instance of this Source and create their own copy of SelectedMoveSource to get or set the selected ID, we subclass SyncedSource.  This ensures that every instance of SelectedMovieSource created anywhere in the app will always have the same value and update when any other instance updates.
final class SelectedMovieSource: SyncedSource<SelectedMovieSource.Model>, CacheResource, ActionSource {
    struct Model {
        let selectedID: Int
        let setSelection: Action<Int>
    }
    struct Actions: ActionMethods {
        var setSelected = ActionMethod(SelectedMovieSource.setSelected)
    }
    struct MutableProperties: SyncedSourcePropertiesProvider {
        var syncProperties = SyncedSourceProperties()
    }
    let cacheIdentifier = "selectedMovie"
    let state: MutableState<MutableProperties>
    init(dependencies: CacheDependency) {
        state = .init(mutableProperties: .init()) { state in .init(selectedID: 0, setSelection: state.setSelected) }
        super.init(state, dependencies: dependencies)
    }
    private func setSelected(_ id: Int) {
        state.setModel(.init(selectedID: id, setSelection: state.setSelected))
    }
}

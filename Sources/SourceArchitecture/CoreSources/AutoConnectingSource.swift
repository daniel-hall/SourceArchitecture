//
//  SourceArchitecture
//
//  Copyright (c) 2023 Daniel Hall
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


private final class AutoConnectingSource<Model>: Source<Model> {

    @Sourced var connectable: Connectable<Model>

    lazy var initialState: Model = {
        connectable.connect()
        return connectable.connected!.value
    }()

    init(_ connectableSource: AnySource<Connectable<Model>>) {
        _connectable = .init(from: connectableSource, updating: AutoConnectingSource.update)
    }

    nonisolated func update(_ value: Connectable<Model>) {
        value.connected.map { state = $0.value }
    }
}

public extension AnySource where Model: ConnectableRepresentable  {
    /// Converts a Source of a `Connectable<Value>` to a Source of the `Value` itself. Will automatically connect the origin Source's model when the Source is subscribed to or the model is accessed.
    func autoConnecting() -> AnySource<Model.Value> {
        AutoConnectingSource(map { $0.asConnectable() }).eraseToAnySource()
    }
}

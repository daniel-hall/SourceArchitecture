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
import Combine


/// A Source that takes in an iOS Progress object, and then translates it to a simple Progress struct which can be monitored by observers
private final class _ProgressSource: Source<Progress> {
    
    let initialState: Progress
    let progress: Foundation.Progress
    @Threadsafe var subscription: AnyObject?
    
    init(progress: Foundation.Progress) {
        self.progress = progress
        initialState = .init(totalUnits: Int(progress.totalUnitCount), completedUnits: Int(progress.completedUnitCount), fractionCompleted: Float(progress.fractionCompleted), estimatedTimeRemaining: progress.estimatedTimeRemaining)
        super.init()
        subscription = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            self?.update(progress)
        }
    }
    
    func update(_ progress: Foundation.Progress) {
        state = .init(totalUnits: Int(progress.totalUnitCount), completedUnits: Int(progress.completedUnitCount), fractionCompleted: Float(progress.fractionCompleted), estimatedTimeRemaining: progress.estimatedTimeRemaining)
        if progress.fractionCompleted >= 1.0 {
            subscription = nil
        }
    }
}

/// A Source that takes in an iOS / Foundation Progress object, and then translates it to a stream of simple Progress struct values which can be monitored by subscribers
public final class ProgressSource: ComposedSource<Progress> {
    public init(_ progress: Foundation.Progress) {
        super.init { _ProgressSource(progress: progress).eraseToAnySource() }
    }
}

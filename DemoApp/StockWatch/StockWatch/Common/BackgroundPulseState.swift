//
//  BackgroundPulseState.swift
//  StockWatch
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



import SwiftUI


/// A convenient type for flashing / pulsing the background of a SwiftUI List cell
final class BackgroundPulseState: ObservableObject {
    @Published public var isPulsing = false
    private var enableWorkItem: DispatchWorkItem?
    private var enabled: Bool
    var backgroundView: some View {
        Color(.displayP3, white: isPulsing ? 0.88 : 1.0, opacity: isPulsing ? 1.0 : 0)
            .padding(.init(top: -6, leading: -40, bottom: -6, trailing: -16))
            .animation(isPulsing ? .easeOut(duration: 0.45) : .easeIn(duration: 0.8), value: isPulsing)
    }
    
    public init(enabled: Bool = true) {
        self.enabled = enabled
    }
    
    public func enable() {
        enableWorkItem?.cancel()
        enableWorkItem = nil
        enabled = true
    }
    
    public func enable(after: TimeInterval) {
        self.enableWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.enabled = true
        }
        self.enableWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: workItem)
    }
    
    public func disable() {
        enableWorkItem?.cancel()
        enableWorkItem = nil
        enabled = false
    }
    
    public func pulse() {
        if !enabled || isPulsing { return }
        isPulsing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.stopPulsing()
        }
    }
    
    public func stopPulsing() {
        if self.isPulsing {
            self.isPulsing = false
        }
    }
}

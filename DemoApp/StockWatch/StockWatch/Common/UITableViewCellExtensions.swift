//
//  UITableViewCellExtensions.swift
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

import UIKit


extension UITableViewCell {
    private struct AssociationKeys {
        static var flashTask = "flashTask"
    }

    private var flashTask: DispatchWorkItem? {
        get { objc_getAssociatedObject(self, &AssociationKeys.flashTask) as? DispatchWorkItem }
        set { objc_setAssociatedObject(self, &AssociationKeys.flashTask, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    func flash() {
        if flashTask != nil { return }
        flashTask?.cancel()
        flashTask = .init { [weak self] in
            self?.backgroundView?.removeFromSuperview()
            self?.backgroundView = nil
            self?.backgroundView = UIView(frame: self?.contentView.bounds ?? .zero)
            self?.backgroundView?.backgroundColor = .clear
            UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState, animations: {[weak self] in self?.backgroundView?.backgroundColor = .init(white: 0.9, alpha: 1) }) {
                UIView.animate(withDuration: $0 ? 0.55 : 0, delay: 0, options: .beginFromCurrentState, animations: { [weak self] in self?.backgroundView?.backgroundColor = .white }, completion: { _ in self?.flashTask = nil })
            }
        }
        DispatchQueue.main.async(execute: flashTask!)
    }

    func stopFlashing() {
        flashTask?.cancel()
        flashTask = nil
        self.backgroundView?.removeFromSuperview()
        self.backgroundView = nil
    }
}

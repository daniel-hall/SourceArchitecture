//
//  Renderer.swift
//  
//
//  Created by Daniel Hall on 4/27/22.
//

import Foundation
import SwiftUI


public protocol Renderer: _Rendering {
    associatedtype Model
    var model: Model { get nonmutating set }
    func render()
}

public struct _RenderTrigger {
    internal let render: Void
}

public extension Renderer {
    subscript(dynamicMember renderTrigger: KeyPath<_RenderTrigger, Void>) -> Void {
        render()
    }
}

@dynamicMemberLookup
public protocol _Rendering {
    subscript(dynamicMember renderTrigger: KeyPath<_RenderTrigger, Void>) -> Void { get }
}

public extension Renderer where Self: View {
    func render() { }
}

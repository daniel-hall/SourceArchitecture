//
//  IEXTokenDecorator.swift
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

import Foundation
import SourceArchitecture

/// A decorator to automatically add my account token to any NetworkResource that makes a request to an IEX endpoint
struct IEXTokenDecoratedResource<DecoratedResource: NetworkResource>: ResourceDecorator, NetworkResource {
    let decoratedResource: DecoratedResource
    var networkURLRequest: URLRequest {
        var networkRequest = decoratedResource.networkURLRequest
        // Make sure we can get the components and that this is an IEX cloud request
        guard let url = networkRequest.url, var components = URLComponents(string: url.absoluteString), components.host?.contains("iexapis") == true else {
            return networkRequest
        }
        // If there is already a token, then just return the existing request
        guard components.queryItems?.first(where: { $0.name == "token"}) == nil else {
            return networkRequest
        }
        //append the account token
        components.queryItems = (components.queryItems ?? []) +
        [.init(name: "token", value: "pk_347d063b83404f13a31cea205999fe45")]
        networkRequest.url = components.url
        return networkRequest
    }
    
    public init(_ resource: DecoratedResource) {
        self.decoratedResource = resource
    }
}

// Make it easy to add the IEX token (if applicable) to any NetworkResource
extension NetworkResource {
    func addingIEXToken() -> IEXTokenDecoratedResource<Self> {
        IEXTokenDecoratedResource(self)
    }
}

// Below we make our decorator adopt the same Resource protocols and conformances as the Resource it is decorating. So any properties or methods we don't explicitly implement in our decorator will pass through to the decorated Resource. In this case, we don't want to change the caching behavior, file behavior, or even other NetworkResource properties like networkRequestTimeout.

extension IEXTokenDecoratedResource: FileResource where DecoratedResource: FileResource {}

extension IEXTokenDecoratedResource: CacheResource where DecoratedResource: CacheResource {}

extension IEXTokenDecoratedResource: UserDefaultsResource  where DecoratedResource: UserDefaultsResource {}

extension IEXTokenDecoratedResource: ResourceElement where DecoratedResource: ResourceElement {}

extension IEXTokenDecoratedResource: EncodableResource where DecoratedResource: EncodableResource {}

extension IEXTokenDecoratedResource: DecodableResource where DecoratedResource: DecodableResource {}

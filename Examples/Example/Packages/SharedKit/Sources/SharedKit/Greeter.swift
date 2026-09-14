//
//  Greeter.swift
//  SharedKit
//
//  Created by Mathew Gacy on 9/7/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

/// A greeting for a given name.
public struct Greeter: Sendable, Equatable {
    /// The name to greet.
    public let name: String

    /// The greeting text.
    public var greeting: String {
        "Hello, \(name)!"
    }

    /// Creates a greeter.
    ///
    /// - Parameter name: The name to greet.
    public init(name: String) {
        self.name = name
    }
}

//
//  GreeterTests.swift
//  SharedKitTests
//
//  Created by Mathew Gacy on 9/7/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import SharedKit
import Testing

struct GreeterTests {

    @Test("Greeting includes the supplied name")
    func greetingIncludesName() {
        #expect(Greeter(name: "world").greeting == "Hello, world!")
    }

    @Test("Greeting includes each platform name", arguments: ["iOS", "macOS"])
    func greetingIncludesPlatform(_ platform: String) {
        #expect(Greeter(name: platform).greeting.contains(platform))
    }
}

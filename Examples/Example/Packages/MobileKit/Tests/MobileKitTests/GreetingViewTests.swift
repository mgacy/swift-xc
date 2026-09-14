//
//  GreetingViewTests.swift
//  MobileKitTests
//
//  Created by Mathew Gacy on 9/7/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import MobileKit
import SharedKit
import Testing
import UIKit

@MainActor
struct GreetingViewTests {

    @Test("Label displays the greeting")
    func labelShowsGreeting() {
        let label = GreetingView.label(for: Greeter(name: "world"))
        #expect(label.text == "Hello, world!")
    }

    @Test("Label has a nonzero intrinsic width")
    func labelSizesToGreeting() {
        let label = GreetingView.label(for: Greeter(name: "iOS"))
        #expect(label.intrinsicContentSize.width > 0)
    }
}

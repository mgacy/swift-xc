//
//  EnvironmentGreeterTests.swift
//  SharedKitEnvironmentTests
//
//  Created by Mathew Gacy on 9/7/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation
import SharedKit
import Testing

struct EnvironmentGreeterTests {

    @Test("Greeting includes the name read from the environment")
    func greetsNameFromEnvironment() {
        setenv("GREETER_NAME", "environment", 1)
        defer { unsetenv("GREETER_NAME") }

        let name = ProcessInfo.processInfo.environment["GREETER_NAME"]
        #expect(Greeter(name: name ?? "").greeting == "Hello, environment!")
    }
}

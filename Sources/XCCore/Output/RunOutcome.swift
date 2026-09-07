//
//  RunOutcome.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

public enum RunOutcome: String, Sendable, Codable {
    case passed
    case infrastructureError = "infrastructure_error"
    case configurationError = "configuration_error"

    public var exitCode: Int32 {
        self == .passed ? 0 : 1
    }
}

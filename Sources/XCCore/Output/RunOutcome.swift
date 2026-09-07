//
//  RunOutcome.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

/// Represents the outcome of a run.
public enum RunOutcome: String, Sendable, Codable {
    /// The run completed successfully.
    case passed
    /// The run failed due to an infrastructure error.
    case infrastructureError = "infrastructure_error"
    /// The run failed due to a configuration error.
    case configurationError = "configuration_error"

    /// The exit code for the run outcome.
    public var exitCode: Int32 {
        self == .passed ? 0 : 1
    }
}

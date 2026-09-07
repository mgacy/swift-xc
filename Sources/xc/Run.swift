//
//  Run.swift
//  xc
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import ArgumentParser
import Foundation
import XCCore

struct Run: ParsableCommand {
    /// Performs the storage probe and emits its final document.
    ///
    /// - Throws: `ResultEncodingError`, `OutputWriteError`, or the nonzero outcome's `ExitCode`.
    func run() throws {
        try Self.emit(RunSession(toolVersion: Version.number).run())
    }

    /// Writes the exact retained bytes before signaling the outcome.
    ///
    /// - Parameters:
    ///   - output: The completed session's bytes and outcome.
    ///   - stdout: The output destination.
    /// - Throws: `OutputWriteError` on a failed write, or `ExitCode` for a nonzero outcome.
    static func emit(_ output: RunSession.Output, stdout: FileHandle = .standardOutput) throws {
        try Termination.write(output.bytes, to: stdout)
        if output.outcome.exitCode != 0 {
            throw ExitCode(output.outcome.exitCode)
        }
    }
}

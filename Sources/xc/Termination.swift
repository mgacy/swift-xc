//
//  Termination.swift
//  xc
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import ArgumentParser
import Foundation
import XCCore

struct OutputWriteError: Error, Sendable {
    let underlyingError: any Error
}

enum Termination {
    /// Emits a terminal message unless the error is an explicit exit code.
    ///
    /// - Parameters:
    ///   - error: A command, parser, or output error.
    ///   - stdout: The result or help destination.
    ///   - stderr: The destination for one-line emission diagnostics.
    /// - Returns: The explicit exit code, 0 for help, 1 for usage, or 2 for emission failure.
    static func code(
        for error: any Error,
        stdout: FileHandle = .standardOutput,
        stderr: FileHandle = .standardError
    ) -> Int32 {
        if let exitCode = error as? ExitCode {
            return exitCode.rawValue
        }
        if error is ResultEncodingError || error is OutputWriteError {
            return emissionFailure(error, stderr: stderr)
        }
        do {
            if XC.exitCode(for: error) == .success {
                let message = XC.fullMessage(for: error)
                try write(Data((message + "\n").utf8), to: stdout)
                return 0
            }
            let document = ProbeResultProjection.configurationError(
                reason: XC.message(for: error), toolVersion: Version.number
            )
            try write(ResultEncoder.encode(document), to: stdout)
            return 1
        } catch {
            return emissionFailure(error, stderr: stderr)
        }
    }

    /// Writes all bytes to a file handle.
    ///
    /// - Parameters:
    ///   - bytes: The bytes to emit unchanged.
    ///   - destination: The output handle.
    /// - Throws: `OutputWriteError` if the write fails; the stream may contain partial bytes.
    static func write(_ bytes: Data, to destination: FileHandle) throws(OutputWriteError) {
        do {
            try destination.write(contentsOf: bytes)
        } catch {
            throw OutputWriteError(underlyingError: error)
        }
    }

    /// - Parameters:
    ///   - error: The encoding or output failure.
    ///   - stderr: The diagnostic destination.
    /// - Returns: Exit status 2, even when the diagnostic cannot be written.
    private static func emissionFailure(_ error: any Error, stderr: FileHandle) -> Int32 {
        let reason = String(describing: error).components(separatedBy: .newlines).joined(separator: " ")
        try? stderr.write(contentsOf: Data("xc: output emission failed: \(reason)\n".utf8))
        return 2
    }
}

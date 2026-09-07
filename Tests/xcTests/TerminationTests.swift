//
//  TerminationTests.swift
//  xcTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import ArgumentParser
import Foundation
import Testing
@testable import xc
@testable import XCCore

@Suite("CLI termination")
struct TerminationTests {
    @Test("Explicit command exit codes propagate without output", arguments: [Int32(0), 1, 2, 37])
    func explicitExit(_ status: Int32) throws {
        let output = Pipe()
        let diagnostics = Pipe()
        #expect(Termination.code(for: ExitCode(status), stdout: output.fileHandleForWriting,
                                 stderr: diagnostics.fileHandleForWriting) == status)
        try output.fileHandleForWriting.close()
        try diagnostics.fileHandleForWriting.close()
        #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
        #expect(diagnostics.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @Test("Clean exits preserve their plain-text message")
    func cleanMessage() throws {
        let output = Pipe()
        let diagnostics = Pipe()
        #expect(Termination.code(for: CleanExit.message("Done"), stdout: output.fileHandleForWriting,
                                 stderr: diagnostics.fileHandleForWriting) == 0)
        try output.fileHandleForWriting.close()
        try diagnostics.fileHandleForWriting.close()
        #expect(output.fileHandleForReading.readDataToEndOfFile() == Data("Done\n".utf8))
        #expect(diagnostics.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @Test("Validation errors emit only configuration JSON")
    func validation() throws {
        let output = Pipe()
        let diagnostics = Pipe()
        #expect(Termination.code(for: ValidationError("Bad input"), stdout: output.fileHandleForWriting,
                                 stderr: diagnostics.fileHandleForWriting) == 1)
        try output.fileHandleForWriting.close()
        try diagnostics.fileHandleForWriting.close()
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let document = try JSONDecoder().decode(ProbeResultDocument.V1.self, from: bytes)
        #expect(document.outcome == .configurationError)
        #expect(document.reason == "Bad input")
        #expect(diagnostics.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @Test("Encoding and closed stdout failures emit one diagnostic", arguments: [true, false])
    func emissionFailure(_ encoding: Bool) throws {
        let output = Pipe()
        let diagnostics = Pipe()
        try output.fileHandleForWriting.close()
        let error: any Error = encoding
            ? ResultEncodingError(underlyingError: NSError(domain: "test\nencoder", code: 1))
            : ValidationError("Bad input")
        #expect(Termination.code(for: error, stdout: output.fileHandleForWriting,
                                 stderr: diagnostics.fileHandleForWriting) == 2)
        try diagnostics.fileHandleForWriting.close()
        let message = try #require(String(data: diagnostics.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        #expect(message.hasPrefix("xc: "))
        #expect(message.filter { $0 == "\n" }.count == 1)
        #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }
}

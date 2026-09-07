//
//  ProcessTests.swift
//  xcTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation
import Testing
@testable import xc
import XCCore

@Suite("CLI process")
struct ProcessTests {
    @Test("Help and version are successful plain text", arguments: [["--help"], ["run", "--help"], ["--version"]])
    func cleanExit(_ arguments: [String]) throws {
        let result = try execute(arguments)
        #expect(result.code == 0)
        #expect(result.stderr.isEmpty)
        let text = try #require(String(data: result.stdout, encoding: .utf8))
        if arguments == ["--version"] {
            #expect(text == Version.number + "\n")
        } else {
            #expect(text.contains("USAGE: xc"))
        }
        #expect((try? JSONSerialization.jsonObject(with: result.stdout)) == nil)
    }

    @Test("Invalid commands and flags emit configuration JSON", arguments: [
        ["unknown"], ["--unknown"], ["run", "--selector", "Example"], ["run", "Example"]
    ])
    func usage(_ arguments: [String]) throws {
        let result = try execute(arguments)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ProbeResultDocument.V1.self, from: result.stdout)
        #expect(result.code == 1)
        #expect(result.stderr.isEmpty)
        #expect(document.outcome == .configurationError)
        #expect(document.reason?.isEmpty == false)
        #expect(document.storage == nil)
        #expect(result.stdout.last == 0x0A)
    }

    @Test("Production run status matches its JSON and any retained artifact")
    func productionRun() throws {
        let result = try execute(["run"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ProbeResultDocument.V1.self, from: result.stdout)
        #expect(result.code == document.outcome.exitCode)
        #expect([RunOutcome.passed, .infrastructureError].contains(document.outcome))
        #expect(result.stderr.isEmpty)
        #expect(document.storage?.locations.count == 6)
        if document.artifacts?.retained == true {
            let path = try #require(document.artifacts?.result)
            #expect(path.hasPrefix("/"))
            #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == result.stdout)
        }
    }

    @Test("Broken stdout returns exit 2 without SIGPIPE termination", arguments: [["run"], ["--help"], ["unknown"]])
    func brokenPipe(_ arguments: [String]) throws {
        let result = try execute(arguments, brokenPipe: true)
        #expect(result.code == 2)
        #expect(result.stdout.isEmpty)
        let diagnostic = try #require(String(data: result.stderr, encoding: .utf8))
        #expect(diagnostic.hasPrefix("xc: output emission failed:"))
        #expect(diagnostic.filter { $0 == "\n" }.count == 1)
    }

    /// - Parameters:
    ///   - arguments: Arguments passed to the built executable.
    ///   - brokenPipe: Whether stdout has no reader.
    /// - Returns: The process status and separately captured streams.
    /// - Throws: Filesystem or process-launch errors.
    private func execute(_ arguments: [String], brokenPipe: Bool = false) throws -> Capture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let diagnostics = try FileHandle(forWritingTo: errorURL)
        defer {
            try? output.close()
            try? diagnostics.close()
        }
        let process = Process()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        process.executableURL = root.appendingPathComponent(".build/debug/xc")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardError = diagnostics
        let pipe = Pipe()
        if brokenPipe {
            try pipe.fileHandleForReading.close()
            process.standardOutput = pipe.fileHandleForWriting
        } else {
            process.standardOutput = output
        }
        try process.run()
        process.waitUntilExit()
        try pipe.fileHandleForWriting.close()
        #expect(process.terminationReason == .exit)
        return Capture(code: process.terminationStatus, stdout: try Data(contentsOf: outputURL),
                       stderr: try Data(contentsOf: errorURL))
    }

    private struct Capture {
        let code: Int32
        let stdout: Data
        let stderr: Data
    }
}

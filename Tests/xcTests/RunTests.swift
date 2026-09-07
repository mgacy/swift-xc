//
//  RunTests.swift
//  xcTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import ArgumentParser
import Foundation
import Testing
@testable import xc
import XCCore

@Suite("CLI run emission")
struct RunTests {
    @Test("Run emits final artifact bytes before signaling its outcome", arguments: [false, true])
    func runEmission(_ failing: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support")
        if failing {
            try Data().write(to: support)
        }
        let session = RunSession(toolVersion: "test", workingDirectory: root,
                                 caches: .success(root.appendingPathComponent("cache")),
                                 applicationSupport: .success(support))
        let result = try session.run()
        #expect(result.outcome == (failing ? .infrastructureError : .passed))
        let path = root.appendingPathComponent("stdout")
        FileManager.default.createFile(atPath: path.path, contents: nil)
        let output = try FileHandle(forWritingTo: path)
        defer { try? output.close() }
        var code: Int32 = 0
        do {
            try Run.emit(result, stdout: output)
        } catch {
            code = try #require(error as? ExitCode).rawValue
        }
        #expect(code == (failing ? 1 : 0))
        #expect(try Data(contentsOf: path) == result.bytes)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ProbeResultDocument.V1.self, from: result.bytes)
        let artifact = try #require(document.artifacts?.result)
        #expect(try Data(contentsOf: URL(fileURLWithPath: artifact)) == result.bytes)
    }
}

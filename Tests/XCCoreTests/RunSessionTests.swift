//
//  RunSessionTests.swift
//  XCCoreTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation
@testable import XCCore
import Testing

@Suite("Run session")
struct RunSessionTests {
    @Test("Retains the exact final bytes and removes disposable probe directories")
    func retainsFinalBytes() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let result = try fixture.session().run()
        let document = try decode(result.bytes)
        #expect(result.outcome == .passed)
        #expect(document.toolVersion == "test-version")
        #expect(document.artifacts?.retained == true)
        let path = try #require(document.artifacts?.result)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == result.bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path) == ["result.json"])
        #expect(document.storage?.locations.count == 6)
        for location in try #require(document.storage?.locations) where location.role != "user_cache_run" {
            #expect(!FileManager.default.fileExists(atPath: try #require(location.path)))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.workspace.appendingPathComponent(".build").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.support.path))
    }

    @Test("An atomic artifact failure re-encodes failure evidence after a successful sweep")
    func artifactWriteFailure() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let identifier = RunIdentifier()
        let identity = try WorkspaceResolver.resolve(workingDirectory: fixture.workspace)
        let directory = StorageRole.userCacheRun.directory(root: fixture.caches, workspaceID: identity.id, runIdentifier: identifier)
        let artifact = directory.appendingPathComponent("result.json")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: true)
        let result = try fixture.session().run(runIdentifier: identifier)
        let document = try decode(result.bytes)
        #expect(result.outcome == .infrastructureError)
        #expect(document.storage?.locations.allSatisfy { $0.completed } == true)
        #expect(document.artifacts?.retained == false)
        let operation = try #require(document.artifacts?.write)
        #expect(operation.kind == "write")
        #expect(operation.path == artifact.path)
        #expect(!operation.succeeded)
        #expect(operation.error?.domain == NSCocoaErrorDomain)
        #expect(operation.error?.message.isEmpty == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["result.json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: artifact.path).isEmpty)
    }

    @Test("A failed location preserves later operations and retains matching failure bytes")
    func locationFailure() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        try Data([1]).write(to: fixture.support)
        let result = try fixture.session().run()
        let document = try decode(result.bytes)
        #expect(result.outcome == .infrastructureError)
        let locations = try #require(document.storage?.locations)
        #expect(locations.count == 6)
        #expect(!locations[3].completed)
        #expect(locations[4].completed)
        #expect(locations[5].completed)
        let path = try #require(document.artifacts?.result)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == result.bytes)
        #expect(try Data(contentsOf: fixture.support) == Data([1]))
    }

    @Test("Unresolved cache roots preserve independent locations without an invented artifact path")
    func cacheResolutionFailure() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        let error = NSError(domain: "RootResolution", code: 19, userInfo: [NSLocalizedDescriptionKey: "Cache unavailable"])
        let result = try RunSession(toolVersion: "test-version", workingDirectory: fixture.workspace,
            caches: .failure(StorageResolutionError(path: nil, underlyingError: error)),
            applicationSupport: .success(fixture.support)).run()
        let document = try decode(result.bytes)
        #expect(result.outcome == .infrastructureError)
        #expect(document.artifacts?.result == nil)
        #expect(document.artifacts?.retained == false)
        #expect(document.artifacts?.write == nil)
        let locations = try #require(document.storage?.locations)
        for location in locations.prefix(3) {
            #expect(location.path == nil)
            #expect(location.operations.count == 1)
            #expect(location.operations.first?.error?.message == error.localizedDescription)
        }
        #expect(locations.suffix(3).allSatisfy { $0.completed })
    }

    @Test("Workspace resolution failure still probes Application Support")
    func workspaceResolutionFailure() throws {
        let fixture = try SessionFixture()
        defer { fixture.remove() }
        try Data("invalid git pointer".utf8).write(to: fixture.workspace.appendingPathComponent(".git"))
        let result = try fixture.session().run()
        let document = try decode(result.bytes)
        #expect(result.outcome == .infrastructureError)
        #expect(document.workspace == nil)
        #expect(document.artifacts?.result == nil)
        let locations = try #require(document.storage?.locations)
        #expect(locations[3].completed)
        #expect(locations.filter { !$0.completed }.count == 5)
        #expect(locations[0].operations.first?.error?.domain == NSCocoaErrorDomain)
    }

    /// - Returns: The final wire document.
    /// - Throws: A decoding error for invalid result bytes.
    private func decode(_ bytes: Data) throws -> ProbeResultDocument.V1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProbeResultDocument.V1.self, from: bytes)
    }
}

private struct SessionFixture {
    let root: URL
    let workspace: URL
    let caches: URL
    let support: URL

    /// - Throws: A filesystem error if the fixture cannot be created.
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        workspace = root.appendingPathComponent("workspace")
        caches = root.appendingPathComponent("caches")
        support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    /// - Returns: A session confined to fixture roots.
    func session() -> RunSession {
        RunSession(toolVersion: "test-version", workingDirectory: workspace,
                   caches: .success(caches), applicationSupport: .success(support))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
